import Foundation

/// Client for the ZTE router web API (the `/goform/...` endpoints used by the
/// MU5001 / MC801A family). It logs in, reads status, and issues band / network
/// mode locks. Every request and response is mirrored to `DiagnosticsLog` so a
/// mismatch on a particular firmware is visible and fixable.
///
/// Authorised use only: this controls the user's *own* router over its local
/// Wi-Fi. No credentials leave the device or the local network.
actor ZTEClient {
    enum ClientError: LocalizedError {
        case badBaseURL
        case notLoggedIn
        case http(Int)
        case loginFailed(String)
        case commandRejected(String)

        var errorDescription: String? {
            switch self {
            case .badBaseURL: return "عنوان الراوتر غير صحيح."
            case .notLoggedIn: return "لم يتم تسجيل الدخول بعد."
            case .http(let c): return "استجابة HTTP غير متوقعة: \(c)"
            case .loginFailed(let r): return "فشل تسجيل الدخول: \(r)"
            case .commandRejected(let r): return "رفض الراوتر الأمر: \(r)"
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    // MARK: - Low-level GET / SET

    /// GET goform_get_cmd_process for one or more comma-separated cmd keys.
    /// Returns the decoded top-level JSON object as [String: String].
    @discardableResult
    func get(_ cmds: [String], multi: Bool = true) async throws -> [String: String] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("goform/goform_get_cmd_process"),
                                  resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "isTest", value: "false"),
                     URLQueryItem(name: "cmd", value: cmds.joined(separator: ","))]
        if multi && cmds.count > 1 { items.append(URLQueryItem(name: "multi_data", value: "1")) }
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        await DiagnosticsLog.shared.add(.request, "GET \(cmds.joined(separator: ","))")
        let (data, resp) = try await session.data(for: req)
        try check(resp)
        let body = String(data: data, encoding: .utf8) ?? ""
        await DiagnosticsLog.shared.add(.response, body)
        return decodeStringDict(data)
    }

    /// POST goform_set_cmd_process with a set of form fields. `AD` is injected
    /// automatically when available.
    @discardableResult
    func set(goformId: String, fields: [String: String], strict: Bool = true) async throws -> [String: String] {
        var body = fields
        body["isTest"] = "false"
        body["goformId"] = goformId
        // LOGIN does not take the AD verification token (that guards
        // authenticated commands), so only compute it afterwards.
        if goformId != "LOGIN", let ad = try? await computeAD() { body["AD"] = ad }

        let url = baseURL.appendingPathComponent("goform/goform_set_cmd_process")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = formEncode(body).data(using: .utf8)

        await DiagnosticsLog.shared.add(.request, "SET \(goformId) \(fields)")
        let (data, resp) = try await session.data(for: req)
        try check(resp)
        let text = String(data: data, encoding: .utf8) ?? ""
        await DiagnosticsLog.shared.add(.response, text)
        let dict = decodeStringDict(data)
        if strict, let result = dict["result"], result != "0", result.lowercased() != "success" {
            throw ClientError.commandRejected(text)
        }
        return dict
    }

    private func loginAccepted(_ dict: [String: String]) -> Bool {
        let r = dict["result"]
        return r == "0" || r?.lowercased() == "success"
    }

    private func freshLD() async -> String {
        ((try? await get(["LD"], multi: false)) ?? [:])["LD"] ?? ""
    }

    // MARK: - High-level operations

    /// Log in with the admin password. ZTE firmwares disagree on the exact
    /// password encoding, so this tries the known schemes in order and stops at
    /// the first the router accepts. Kept to a handful of attempts because ZTE
    /// units lock out after ~5 failures — so the caller must be sure the
    /// password itself is correct before invoking this.
    func login(password: String) async throws {
        let shaUpper = ZTECrypto.sha256Hex(password)
        let shaLower = shaUpper.lowercased()

        func tryLogin(_ token: String, _ note: String) async -> Bool {
            let accepted = loginAccepted((try? await set(goformId: "LOGIN",
                                                         fields: ["password": token],
                                                         strict: false)) ?? [:])
            if !accepted { await DiagnosticsLog.shared.add(.note, "طريقة \(note) لم تُقبل.") }
            return accepted
        }

        // 1) base64(password) — used by MU5001 firmwares that return an empty LD.
        if await tryLogin(Data(password.utf8).base64EncodedString(), "base64") { return }

        // 2) SHA256( SHA256(pw) + LD ) — only when the firmware supplies an LD.
        let ld = await freshLD()
        if !ld.isEmpty, await tryLogin(ZTECrypto.sha256Hex(shaUpper + ld), "SHA256+LD") { return }

        // 3) plain SHA256(pw) — CryptoJS-style lower-case, then upper-case.
        if await tryLogin(shaLower, "SHA256(lower)") { return }
        if await tryLogin(shaUpper, "SHA256(upper)") { return }

        throw ClientError.loginFailed("رُفضت طرق تسجيل الدخول المعروفة. تأكد أنها كلمة مرور صفحة الإدارة (وليست كلمة مرور الواي فاي)، وافتح تبويب «السجل» وأرسله لي.")
    }

    func fetchStatus() async throws -> RouterStatus {
        RouterStatus(raw: try await get(RouterStatus.queryKeys))
    }

    /// Lock the modem to the given network mode (RAT).
    func setNetworkMode(_ mode: NetworkMode) async throws {
        try await set(goformId: "SET_BEARER_PREFERENCE",
                      fields: ["BearerPreference": mode.bearerPreference])
    }

    /// Lock LTE and/or 5G-NR bands. Empty set = leave that RAT unlocked (auto).
    /// Sends the documented ZTE band-lock command with both masks.
    func lockBands(lte: Set<Int>, nr5g: Set<Int>) async throws {
        var fields: [String: String] = [
            "is_gw_band": "0",
            "gw_band_mask": "0",
            "is_lte_band": lte.isEmpty ? "0" : "1",
            "lte_band_mask": RadioBand.hexMask(for: lte),
            "is_nr5g_band": nr5g.isEmpty ? "0" : "1",
            "nr5g_band_mask": RadioBand.hexMask(for: nr5g),
        ]
        // Some firmwares expect the newer key names too; send both harmlessly.
        fields["lte_band_lock"] = RadioBand.hexMask(for: lte)
        fields["nr5g_band_lock"] = RadioBand.hexMask(for: nr5g)
        try await set(goformId: "SET_LOCK_BAND", fields: fields)
    }

    /// Clear any band lock (return to automatic band selection).
    func clearBandLock() async throws {
        try await set(goformId: "SET_LOCK_BAND",
                      fields: ["is_gw_band": "0", "gw_band_mask": "0",
                               "is_lte_band": "0", "lte_band_mask": "0",
                               "is_nr5g_band": "0", "nr5g_band_mask": "0"])
    }

    /// Send an arbitrary goform set command (advanced / troubleshooting).
    func sendRaw(goformId: String, fields: [String: String]) async throws -> [String: String] {
        try await set(goformId: goformId, fields: fields)
    }

    // MARK: - Internals

    /// AD = MD5( MD5(wa_inner_version + cr_version) + RD ). Returns nil if the
    /// firmware doesn't expose these (older units don't require AD).
    private func computeAD() async throws -> String? {
        let versions = try await get(["wa_inner_version", "cr_version"])
        guard let wa = versions["wa_inner_version"], let cr = versions["cr_version"],
              !wa.isEmpty else { return nil }
        let rd = try await get(["RD"], multi: false)["RD"] ?? ""
        guard !rd.isEmpty else { return nil }
        return ZTECrypto.adToken(waInnerVersion: wa, crVersion: cr, rd: rd)
    }

    private func check(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode)
        }
    }

    private func decodeStringDict(_ data: Data) -> [String: String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var out: [String: String] = [:]
        for (k, v) in obj {
            if let s = v as? String { out[k] = s }
            else if let n = v as? NSNumber { out[k] = n.stringValue }
        }
        return out
    }

    private func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}

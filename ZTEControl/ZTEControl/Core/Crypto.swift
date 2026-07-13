import Foundation
import CryptoKit

/// Hashing helpers for the ZTE web API authentication scheme.
///
/// ZTE's router web UI authenticates with SHA-256 and guards state-changing
/// commands with an MD5 "AD" token derived from the firmware versions and a
/// per-request nonce (RD). Both are computed client-side and sent back.
enum ZTECrypto {
    /// Uppercase hex SHA-256 of a UTF-8 string (ZTE uses upper-case hex).
    static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    /// Uppercase hex MD5 of a UTF-8 string.
    static func md5Hex(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    /// Login password token: SHA256( SHA256(password) + LD ).
    /// `ld` is the nonce returned by `cmd=LD`.
    static func loginToken(password: String, ld: String) -> String {
        sha256Hex(sha256Hex(password) + ld)
    }

    /// CSRF/verification token for set commands:
    /// AD = MD5( MD5(wa_inner_version + cr_version) + RD ).
    static func adToken(waInnerVersion: String, crVersion: String, rd: String) -> String {
        md5Hex(md5Hex(waInnerVersion + crVersion) + rd)
    }
}

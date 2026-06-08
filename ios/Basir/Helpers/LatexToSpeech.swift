// LatexToSpeech.swift
// Deterministic LaTeX → spoken-text converter. Direct port of Android's
// LatexToSpeech.java (v3.0).
//
// Why this exists — and why it is ECONOMICAL
// ──────────────────────────────────────────
//   The old math flow asked Gemini to emit BOTH a spoken description AND
//   LaTeX in one response. That doubled the output length (≈2× output
//   tokens = ≈2× cost), exhausted the token budget on dense pages, and
//   depended on the model perfectly following a long format rule.
//
//   This splits the work: Gemini emits ONLY compact LaTeX — small,
//   well-defined output it is highly trained on, so a cheaper/faster
//   model suffices — and the spoken Arabic / English form is rendered
//   here, on-device, for free. The spoken conversion is deterministic:
//   it never truncates, never costs a token, and is identical every run.
//
// Coverage: K-12 / university math — arithmetic, algebra, calculus,
// trigonometry, basic set theory, Greek letters, sub/superscripts,
// fractions, roots, integrals, sums, products, limits, simple matrices.
// Unknown LaTeX commands fall back to their literal name (\foo → "foo").

import Foundation

enum LatexToSpeech {

    /// Convert a single LaTeX expression to a spoken-form string.
    static func convert(_ latex: String, arabic: Bool) -> String {
        var s = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        // Strip outer $...$ or $$...$$ if present.
        if s.hasPrefix("$$"), s.hasSuffix("$$"), s.count >= 4 {
            s = String(s.dropFirst(2).dropLast(2))
        } else if s.hasPrefix("$"), s.hasSuffix("$"), s.count >= 2 {
            s = String(s.dropFirst().dropLast())
        }
        let sc = Scanner(s)
        var out = ""
        render(sc, &out, arabic)
        return clean(out)
    }

    // MARK: - Scanner: a tiny cursor over the LaTeX string

    private final class Scanner {
        let chars: [Character]
        var p = 0
        init(_ s: String) { chars = Array(s) }

        var more: Bool { p < chars.count }
        func peek() -> Character { more ? chars[p] : "\0" }
        @discardableResult func next() -> Character { let c = chars[p]; p += 1; return c }
        func skipWs() { while more, peek().isWhitespace { p += 1 } }

        private func slice(_ lo: Int, _ hi: Int) -> String {
            guard lo < hi, lo >= 0, hi <= chars.count else { return "" }
            return String(chars[lo..<hi])
        }

        /// Read a \command starting at the current backslash. Returns the
        /// full "\name" including the backslash.
        func readCommand() -> String {
            if peek() != "\\" { return "" }
            p += 1
            if !more { return "\\" }
            let c = peek()
            if !c.isLetter { p += 1; return "\\" + String(c) }
            let start = p
            while more, peek().isLetter { p += 1 }
            return "\\" + slice(start, p)
        }

        /// Read a {...} group (balanced) and return its content.
        func readGroup() -> String {
            if peek() != "{" { return "" }
            p += 1
            var depth = 1
            let start = p
            while more, depth > 0 {
                let c = next()
                if c == "\\", more { p += 1; continue }   // escaped char
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return slice(start, p - 1) }
                }
            }
            return slice(start, chars.count)
        }

        /// Read an optional [...] argument (used by \sqrt[n]{}).
        func readBracketGroup() -> String {
            if peek() != "[" { return "" }
            p += 1
            let start = p
            while more, peek() != "]" { p += 1 }
            let r = slice(start, p)
            if more { p += 1 }
            return r
        }

        /// Read the next argument: either a {group} or a single token.
        func readArg() -> String {
            skipWs()
            if peek() == "{" { return readGroup() }
            if peek() == "\\" { return readCommand() }
            if more { return String(next()) }
            return ""
        }

        /// Consume everything up to and including \end{env}; return the body.
        func readUntilEnd(_ env: String) -> String {
            let marker = Array("\\end{" + env + "}")
            var i = p
            while i <= chars.count - marker.count {
                if Array(chars[i..<(i + marker.count)]) == marker {
                    let body = slice(p, i)
                    p = i + marker.count
                    return body
                }
                i += 1
            }
            let body = slice(p, chars.count)
            p = chars.count
            return body
        }
    }

    // MARK: - Main render loop

    private static func render(_ sc: Scanner, _ out: inout String, _ ar: Bool) {
        while sc.more {
            let c = sc.peek()
            if c == "\\" {
                handleCommand(sc.readCommand(), sc, &out, ar)
            } else if c == "{" {
                let inner = sc.readGroup()
                out += " "
                render(Scanner(inner), &out, ar)
                out += " "
            } else if c == "^" {
                sc.next()
                let arg = sc.readArg()
                out += " " + superKey(arg, ar)
                if !isSimplePower(arg) {
                    out += " "
                    render(Scanner(arg), &out, ar)
                }
                out += " "
            } else if c == "_" {
                sc.next()
                let arg = sc.readArg()
                out += ar ? " تحت " : " sub "
                render(Scanner(arg), &out, ar)
                out += " "
            } else if c == "+" { sc.next(); out += ar ? " زائد " : " plus " }
            else if c == "-" { sc.next(); out += ar ? " ناقص " : " minus " }
            else if c == "=" { sc.next(); out += ar ? " يساوي " : " equals " }
            else if c == "/" { sc.next(); out += ar ? " على " : " over " }
            else if c == "*" { sc.next(); out += ar ? " ضرب " : " times " }
            else if c == "<" { sc.next(); out += ar ? " أصغر من " : " less than " }
            else if c == ">" { sc.next(); out += ar ? " أكبر من " : " greater than " }
            else if c == "," { sc.next(); out += ar ? "، " : ", " }
            else if c == ";" { sc.next(); out += ar ? "؛ " : "; " }
            else if c == "." { sc.next(); out += "." }
            else if c == "(" { sc.next(); out += ar ? " مفتوح قوس " : " open paren " }
            else if c == ")" { sc.next(); out += ar ? " مغلق قوس " : " close paren " }
            else if c == "[" { sc.next(); out += ar ? " مفتوح قوس مربع " : " open bracket " }
            else if c == "]" { sc.next(); out += ar ? " مغلق قوس مربع " : " close bracket " }
            else if c == "|" { sc.next(); out += ar ? " القيمة المطلقة لـ " : " absolute value of " }
            else if c == "!" { sc.next(); out += ar ? " مضروب " : " factorial " }
            else if c == "'" { sc.next(); out += ar ? " مشتقة " : " prime " }
            else if c.isNumber {
                var num = ""
                while sc.more, sc.peek().isNumber || sc.peek() == "." { num.append(sc.next()) }
                out += " " + num + " "
            } else if c.isLetter || isArabicLetter(c) {
                sc.next()
                out += " " + letterName(c, ar) + " "
            } else if c.isWhitespace {
                sc.next()
            } else {
                sc.next()   // unknown character: skip silently
            }
        }
    }

    // MARK: - Command handlers

    private static func handleCommand(_ cmd: String, _ sc: Scanner,
                                      _ out: inout String, _ ar: Bool) {
        if let greek = greekLetter(cmd, ar) { out += " " + greek + " "; return }
        if let fn = functionName(cmd, ar) { out += " " + fn + " "; return }
        if let op = operatorName(cmd, ar) { out += " " + op + " "; return }

        // Spacing / formatting commands: silently consume.
        switch cmd {
        case "\\,", "\\;", "\\:", "\\!", "\\quad", "\\qquad",
             "\\left", "\\right", "\\bigl", "\\bigr", "\\Bigl", "\\Bigr":
            return
        case "\\\\":
            out += ar ? "، الصف التالي " : ", next row "
            return
        default: break
        }

        // Composite commands with arguments.
        switch cmd {
        case "\\frac", "\\dfrac", "\\tfrac":
            renderFraction(sc, &out, ar); return
        case "\\sqrt":
            renderRoot(sc, &out, ar); return
        case "\\int":
            out += ar ? " تكامل " : " integral "
            renderSubSup(sc, &out, ar, sumLike: true); return
        case "\\iint":
            out += ar ? " تكامل مزدوج " : " double integral "
            renderSubSup(sc, &out, ar, sumLike: true); return
        case "\\iiint":
            out += ar ? " تكامل ثلاثي " : " triple integral "
            renderSubSup(sc, &out, ar, sumLike: true); return
        case "\\oint":
            out += ar ? " تكامل خطّي " : " contour integral "
            renderSubSup(sc, &out, ar, sumLike: true); return
        case "\\sum":
            out += ar ? " مجموع " : " sum "
            renderSubSup(sc, &out, ar, sumLike: true); return
        case "\\prod":
            out += ar ? " حاصل ضرب " : " product "
            renderSubSup(sc, &out, ar, sumLike: true); return
        case "\\lim":
            out += ar ? " نهاية عندما " : " limit as "
            renderSubSup(sc, &out, ar, sumLike: false); return
        case "\\limsup":
            out += ar ? " نهاية عليا " : " limit superior "
            renderSubSup(sc, &out, ar, sumLike: false); return
        case "\\liminf":
            out += ar ? " نهاية دنيا " : " limit inferior "
            renderSubSup(sc, &out, ar, sumLike: false); return
        case "\\bar", "\\overline":
            let arg = sc.readArg()
            render(Scanner(arg), &out, ar)
            out += ar ? " شرطة علوية " : " bar "; return
        case "\\hat", "\\widehat":
            let arg = sc.readArg()
            render(Scanner(arg), &out, ar)
            out += ar ? " قبعة " : " hat "; return
        case "\\vec":
            let arg = sc.readArg()
            out += ar ? " متجه " : " vector "
            render(Scanner(arg), &out, ar)
            out += " "; return
        case "\\begin":
            let env = sc.readArg()
            if env.contains("matrix") || env.contains("array") {
                out += ar ? " مصفوفة: " : " matrix: "
                var body = sc.readUntilEnd(env)
                body = body.replacingOccurrences(of: "&", with: ar ? "، " : ", ")
                           .replacingOccurrences(of: "\\\\", with: ar ? " ؛ " : " ; ")
                render(Scanner(body), &out, ar)
            }
            return
        case "\\end":
            _ = sc.readArg(); return
        case "\\text", "\\textrm", "\\mathrm", "\\textit",
             "\\mathbf", "\\boldsymbol", "\\mathit":
            let arg = sc.readArg()
            out += " " + arg + " "; return
        case "\\dots", "\\ldots", "\\cdots":
            out += ar ? " ... " : " dot dot dot "; return
        default: break
        }

        // Unknown command — emit its tail so the user sees what was missed.
        if cmd.count > 1 {
            out += " " + String(cmd.dropFirst()) + " "
        }
    }

    private static func renderFraction(_ sc: Scanner, _ out: inout String, _ ar: Bool) {
        let num = sc.readArg()
        let den = sc.readArg()
        render(Scanner(num), &out, ar)
        out += ar ? " على " : " over "
        render(Scanner(den), &out, ar)
        out += " "
    }

    private static func renderRoot(_ sc: Scanner, _ out: inout String, _ ar: Bool) {
        sc.skipWs()
        var index = ""
        if sc.peek() == "[" { index = sc.readBracketGroup().trimmingCharacters(in: .whitespaces) }
        let arg = sc.readArg()
        if index.isEmpty {
            out += ar ? " الجذر التربيعي لـ " : " the square root of "
        } else if index == "3" {
            out += ar ? " الجذر التكعيبي لـ " : " the cube root of "
        } else if ar {
            out += " الجذر النوني "
        } else {
            out += " the " + index + "th root of "
        }
        render(Scanner(arg), &out, ar)
        out += " "
    }

    /// Pick up an optional sub/superscript that immediately follows a
    /// sum/integral/lim and verbalise it.
    private static func renderSubSup(_ sc: Scanner, _ out: inout String,
                                     _ ar: Bool, sumLike: Bool) {
        sc.skipWs()
        var lo: String?
        var hi: String?
        if sc.peek() == "_" { sc.next(); lo = sc.readArg(); sc.skipWs() }
        if sc.peek() == "^" { sc.next(); hi = sc.readArg() }
        else if sc.peek() == "_" { sc.next(); lo = sc.readArg(); sc.skipWs() }
        if let lo {
            out += ar ? (sumLike ? " من " : " ") : (sumLike ? " from " : " ")
            render(Scanner(lo), &out, ar)
            out += " "
        }
        if let hi {
            out += ar ? " إلى " : " to "
            render(Scanner(hi), &out, ar)
            out += " "
        }
        if sumLike { out += ar ? "للقيمة " : "of " }
    }

    // MARK: - Lookup tables

    private static func greekLetter(_ cmd: String, _ ar: Bool) -> String? {
        guard let pair = greek[cmd] else { return nil }
        return ar ? pair.0 : pair.1
    }

    private static let greek: [String: (String, String)] = [
        "\\alpha": ("ألفا", "alpha"), "\\beta": ("بيتا", "beta"),
        "\\gamma": ("غاما", "gamma"), "\\delta": ("دلتا", "delta"),
        "\\epsilon": ("إبسلون", "epsilon"), "\\varepsilon": ("إبسلون", "epsilon"),
        "\\zeta": ("زيتا", "zeta"), "\\eta": ("إيتا", "eta"),
        "\\theta": ("ثيتا", "theta"), "\\vartheta": ("ثيتا", "theta"),
        "\\iota": ("أيوتا", "iota"), "\\kappa": ("كابا", "kappa"),
        "\\lambda": ("لامبدا", "lambda"), "\\mu": ("ميو", "mu"),
        "\\nu": ("نيو", "nu"), "\\xi": ("كساي", "xi"),
        "\\pi": ("باي", "pi"), "\\rho": ("رو", "rho"),
        "\\sigma": ("سيغما", "sigma"), "\\tau": ("تاو", "tau"),
        "\\upsilon": ("أبسلون", "upsilon"), "\\phi": ("فاي", "phi"),
        "\\varphi": ("فاي", "phi"), "\\chi": ("خاي", "chi"),
        "\\psi": ("بساي", "psi"), "\\omega": ("أوميغا", "omega"),
        "\\Gamma": ("غاما الكبيرة", "capital gamma"),
        "\\Delta": ("دلتا الكبيرة", "capital delta"),
        "\\Theta": ("ثيتا الكبيرة", "capital theta"),
        "\\Lambda": ("لامبدا الكبيرة", "capital lambda"),
        "\\Xi": ("كساي الكبيرة", "capital xi"),
        "\\Pi": ("باي الكبيرة", "capital pi"),
        "\\Sigma": ("سيغما الكبيرة", "capital sigma"),
        "\\Phi": ("فاي الكبيرة", "capital phi"),
        "\\Psi": ("بساي الكبيرة", "capital psi"),
        "\\Omega": ("أوميغا الكبيرة", "capital omega"),
    ]

    private static func functionName(_ cmd: String, _ ar: Bool) -> String? {
        switch cmd {
        case "\\sin": return ar ? "جا" : "sine"
        case "\\cos": return ar ? "جتا" : "cosine"
        case "\\tan": return ar ? "ظا" : "tangent"
        case "\\cot": return ar ? "ظتا" : "cotangent"
        case "\\sec": return ar ? "قاطع" : "secant"
        case "\\csc": return ar ? "قاطع تمام" : "cosecant"
        case "\\arcsin": return ar ? "قوس جا" : "arcsine"
        case "\\arccos": return ar ? "قوس جتا" : "arccosine"
        case "\\arctan": return ar ? "قوس ظا" : "arctangent"
        case "\\sinh": return ar ? "جا زائدية" : "hyperbolic sine"
        case "\\cosh": return ar ? "جتا زائدية" : "hyperbolic cosine"
        case "\\tanh": return ar ? "ظا زائدية" : "hyperbolic tangent"
        case "\\log": return ar ? "لوغاريتم" : "log"
        case "\\ln": return ar ? "لوغاريتم طبيعي" : "natural log"
        case "\\exp": return ar ? "أُسّي" : "exponential"
        case "\\max": return ar ? "أكبر قيمة" : "max"
        case "\\min": return ar ? "أصغر قيمة" : "min"
        case "\\det": return ar ? "محدّد" : "determinant"
        case "\\dim": return ar ? "بعد" : "dimension"
        case "\\deg": return ar ? "درجة" : "degree"
        case "\\arg": return ar ? "سعة" : "argument"
        case "\\mod": return ar ? "باقي" : "mod"
        default: return nil
        }
    }

    private static func operatorName(_ cmd: String, _ ar: Bool) -> String? {
        switch cmd {
        case "\\leq", "\\le": return ar ? " أصغر من أو يساوي " : " less than or equal to "
        case "\\geq", "\\ge": return ar ? " أكبر من أو يساوي " : " greater than or equal to "
        case "\\neq", "\\ne": return ar ? " لا يساوي " : " not equal to "
        case "\\approx": return ar ? " يقارب " : " approximately equal to "
        case "\\equiv": return ar ? " يكافئ " : " equivalent to "
        case "\\times": return ar ? " ضرب " : " times "
        case "\\cdot": return ar ? " ضرب " : " dot "
        case "\\div": return ar ? " قسمة " : " divided by "
        case "\\pm": return ar ? " زائد أو ناقص " : " plus or minus "
        case "\\mp": return ar ? " ناقص أو زائد " : " minus or plus "
        case "\\infty": return ar ? " ما لا نهاية " : " infinity "
        case "\\partial": return ar ? " مشتقة جزئية " : " partial "
        case "\\nabla": return ar ? " نابلا " : " nabla "
        case "\\in": return ar ? " ينتمي إلى " : " in "
        case "\\notin": return ar ? " لا ينتمي إلى " : " not in "
        case "\\subset": return ar ? " مجموعة جزئية من " : " subset of "
        case "\\subseteq": return ar ? " مجموعة جزئية أو يساوي " : " subset or equal "
        case "\\supset": return ar ? " مجموعة فوقية " : " superset of "
        case "\\cup": return ar ? " اتحاد " : " union "
        case "\\cap": return ar ? " تقاطع " : " intersection "
        case "\\emptyset": return ar ? " مجموعة فارغة " : " empty set "
        case "\\forall": return ar ? " لكل " : " for all "
        case "\\exists": return ar ? " يوجد " : " there exists "
        case "\\neg": return ar ? " ليس " : " not "
        case "\\land": return ar ? " و " : " and "
        case "\\lor": return ar ? " أو " : " or "
        case "\\to": return ar ? " يؤول إلى " : " approaches "
        case "\\rightarrow": return ar ? " يستلزم " : " implies "
        case "\\Rightarrow": return ar ? " يستلزم " : " implies "
        case "\\leftarrow": return ar ? " مستلزَم من " : " implied by "
        case "\\leftrightarrow": return ar ? " إذا وفقط إذا " : " if and only if "
        case "\\iff": return ar ? " إذا وفقط إذا " : " if and only if "
        case "\\mapsto": return ar ? " يُرسَل إلى " : " maps to "
        case "\\bot": return ar ? " متعامد " : " perpendicular "
        case "\\angle": return ar ? " زاوية " : " angle "
        case "\\triangle": return ar ? " مثلّث " : " triangle "
        case "\\circ": return ar ? " درجة " : " degree "
        case "\\prime": return ar ? " شَرطة " : " prime "
        case "\\Re": return ar ? " الجزء الحقيقي " : " real part "
        case "\\Im": return ar ? " الجزء التخيُّلي " : " imaginary part "
        default: return nil
        }
    }

    /// Common power names: ^2 → "squared", ^3 → "cubed", ^-1 → "inverse".
    private static func superKey(_ arg: String, _ ar: Bool) -> String {
        let t = arg.trimmingCharacters(in: .whitespaces)
        if t == "2" { return ar ? "تربيع" : "squared" }
        if t == "3" { return ar ? "تكعيب" : "cubed" }
        if t == "-1" || t == "{-1}" { return ar ? "معكوس" : "inverse" }
        return ar ? "أُسّ" : "to the power of"
    }

    private static func isSimplePower(_ arg: String) -> Bool {
        let t = arg.trimmingCharacters(in: .whitespaces)
        return t == "2" || t == "3" || t == "-1" || t == "{-1}"
    }

    /// Map a single math letter to a spoken name. In Arabic mode the
    /// canonical variable letters (x→س, y→ص, …) get their expected Arabic
    /// equivalent; the rest stay Latin for the TTS engine to pronounce.
    private static func letterName(_ c: Character, _ ar: Bool) -> String {
        if !ar { return String(c) }
        switch c {
        case "x": return "س"
        case "y": return "ص"
        case "z": return "ع"
        case "n": return "ن"
        case "k": return "ك"
        case "m": return "م"
        case "i": return "i"   // imaginary unit: keep Latin
        case "e": return "e"   // Euler's number: keep Latin
        default: return String(c)
        }
    }

    private static func isArabicLetter(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return v >= 0x0600 && v <= 0x06FF
    }

    // MARK: - Mixed prose + math

    /// Convert a model response that contains prose with inline / display
    /// LaTeX (wrapped in $…$, $$…$$, \(…\), or \[…\]) into fully spoken
    /// text. Each math span becomes its spoken form followed by a
    /// "[LaTeX: …]" trailer for review; prose passes through untouched.
    /// This is what lets Gemini emit only compact LaTeX (cheap) while the
    /// user still hears natural math.
    static func renderDocument(_ text: String, arabic: Bool) -> String {
        let chars = Array(text)
        var out = ""
        var i = 0

        func emit(_ latex: String) {
            let raw = latex.trimmingCharacters(in: .whitespacesAndNewlines)
            let spoken = convert(latex, arabic: arabic)
            if spoken.isEmpty { out += raw }
            else { out += spoken + " [LaTeX: " + raw + "]" }
        }
        /// Index of the next single character `ch` at/after `from`.
        func findChar(_ from: Int, _ ch: Character) -> Int? {
            var j = from
            while j < chars.count { if chars[j] == ch { return j }; j += 1 }
            return nil
        }
        /// Index of the next two-character closer `a`+`b` at/after `from`.
        func findPair(_ from: Int, _ a: Character, _ b: Character) -> Int? {
            var j = from
            while j + 1 < chars.count {
                if chars[j] == a && chars[j + 1] == b { return j }
                j += 1
            }
            return nil
        }

        while i < chars.count {
            let c = chars[i]
            let nextC = i + 1 < chars.count ? chars[i + 1] : "\0"
            if c == "$", nextC == "$", let close = findPair(i + 2, "$", "$") {
                emit(String(chars[(i + 2)..<close])); i = close + 2; continue
            }
            if c == "\\", nextC == "[", let close = findPair(i + 2, "\\", "]") {
                emit(String(chars[(i + 2)..<close])); i = close + 2; continue
            }
            if c == "\\", nextC == "(", let close = findPair(i + 2, "\\", ")") {
                emit(String(chars[(i + 2)..<close])); i = close + 2; continue
            }
            if c == "$", let close = findChar(i + 1, "$") {
                emit(String(chars[(i + 1)..<close])); i = close + 1; continue
            }
            out.append(c)
            i += 1
        }
        return out
    }

    private static func clean(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "[\\s\\u00A0]+", with: " ",
                                         options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        out = out.replacingOccurrences(of: "\\s+([,.;؛،])", with: "$1",
                                       options: .regularExpression)
        out = out.replacingOccurrences(of: "\\(\\s+", with: "(",
                                       options: .regularExpression)
        out = out.replacingOccurrences(of: "\\s+\\)", with: ")",
                                       options: .regularExpression)
        return out
    }
}

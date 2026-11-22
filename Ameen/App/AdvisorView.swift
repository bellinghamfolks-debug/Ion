import SwiftUI

private enum AdvisorMode: String, CaseIterable {
    case ledger = "دفتري", research = "مصادر عامة", model = "نموذج سحابي"
}
private struct Exchange: Identifiable {
    let id = UUID()
    let question: String
    let reply: AdvisorReply
    let mode: AdvisorMode
    let shared: Bool
}
struct AdvisorView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var mode: AdvisorMode = .ledger
    @State private var question = ""
    @State private var turns: [Exchange] = []
    @State private var web = true
    @State private var share = false
    @State private var settings = false
    @State private var installment = ""
    @State private var calculation: String?
    @State private var error: String?
    @State private var busy = false
    @State private var request: Task<Void,Never>?
    @State private var requestID: UUID?
    @AccessibilityFocusState private var focusedAnswer: Bool
    @FocusState private var keyboard: Bool
    private var prompts: [String] {
        switch mode {
        case .ledger: return ["كم أصرف يوميًا حتى نهاية الشهر؟","قارن مصروفاتي بالشهر الماضي","ما أقرب استحقاق؟","أين كانت أكبر مصروفاتي؟"]
        case .research: return ["التضخم في السعودية","البطالة في السعودية","ما معنى الفائدة المركبة؟"]
        case .model: return ["كيف أقارن بين خطتين لسداد الدين؟","اشرح لي التكلفة الفعلية للتمويل مع مثال"]
        }
    }
    var body: some View {
        List {
            Section {
                Picker("مصدر الاستشارة", selection:$mode) { ForEach(AdvisorMode.allCases, id:\.self) { Text($0.rawValue).tag($0) } }
                if mode == .model {
                    Toggle("البحث في الويب وإرفاق المراجع", isOn:$web)
                    Toggle("إرفاق إجماليات دفتري", isOn:$share)
                    if share { DisclosureGroup("معاينة الإجماليات المرسلة") { Text(LedgerReport(store.book).summary) } }
                    Button("إعداد مفتاح OpenAI") { settings = true }
                    Text("يرسل السؤال وسياق المحادثة السحابية إلى OpenAI. تُحسب تكلفة النموذج والبحث على حساب API الخاص بك.").font(.footnote)
                } else if mode == .research {
                    Text("تُرسَل عبارة البحث إلى المصدر العام. اختر مؤشرًا سعوديًا للبنك الدولي أو موضوعًا للبحث في ويكيبيديا العربية.").font(.footnote)
                }
            }
            Section("اسأل أمين") {
                TextField("اكتب أو أملِ سؤالك", text:$question, axis:.vertical).lineLimit(2...6).focused($keyboard)
                if busy { HStack { ProgressView(); Text("يجري إعداد الإجابة"); Spacer(); Button("إلغاء") { cancel() } } }
                else { Button { ask() } label: { Label("إرسال السؤال",systemImage:"paperplane.fill") }.disabled(question.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            if let latest = turns.last(where: { $0.mode == mode }) {
                Section("آخر إجابة") { transcript(latest).accessibilityFocused($focusedAnswer) }
                let older = turns.filter { $0.mode == mode && $0.id != latest.id }
                if !older.isEmpty { DisclosureGroup("الأسئلة السابقة") { ForEach(older.reversed()) { transcript($0) } } }
            }
            Section("أسئلة مقترحة") { ForEach(prompts,id:\.self) { q in Button(q) { question=q; error=nil }.disabled(busy) } }
            if mode == .ledger {
                Section("محاكاة سداد ديوني") {
                    TextField("المتاح شهريًا للسداد بالريال",text:$installment).keyboardType(.decimalPad)
                    Button("احسب مدة السداد") {
                        calculation = store.loadError ?? Money.parse(installment).flatMap { LedgerReport(store.book).payoff(monthly:$0) } ?? "أدخل مبلغًا شهريًا موجبًا."
                        UIAccessibility.post(notification:.announcement,argument:calculation)
                    }
                    if let calculation { Text(calculation) }
                }
            }
        }.navigationTitle("مستشار أمين")
        .onChange(of: mode) { _, _ in cancel(); error=nil; question="" }
        .onDisappear { cancel() }
        .sheet(isPresented:$settings) { NavigationStack { ModelSettings() } }
    }
    private func transcript(_ turn: Exchange) -> some View {
        VStack(alignment:.leading,spacing:10) {
            Text(turn.question).font(.headline)
            Text(turn.reply.origin).font(.caption.bold()).foregroundStyle(Theme.teal)
            Text(linkedText(turn.reply)).textSelection(.enabled)
            ForEach(turn.reply.sources) { source in Link(source.title, destination:source.url).accessibilityLabel("المصدر: " + source.title) }
        }.padding(.vertical,4)
    }
    private func linkedText(_ reply: AdvisorReply) -> AttributedString {
        let value = NSMutableAttributedString(string:reply.text)
        let scalars = reply.text.unicodeScalars
        for citation in reply.citations {
            guard let a = scalars.index(scalars.startIndex,offsetBy:citation.start,limitedBy:scalars.endIndex),
                  let b = scalars.index(scalars.startIndex,offsetBy:citation.end,limitedBy:scalars.endIndex) else { continue }
            value.addAttribute(.link,value:citation.url,range:NSRange(a..<b,in:reply.text))
        }
        return (try? AttributedString(value, including: \.uiKit)) ?? AttributedString(reply.text)
    }
    private func cancel() { request?.cancel(); request = nil; requestID=nil; busy=false }
    @MainActor private func ask() {
        let q = question.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !busy, !q.isEmpty else { return }
        guard q.count <= 2000 else { error="اختصر السؤال إلى ٢٠٠٠ حرف."; return }
        if (mode == .ledger || (mode == .model && share)), let failure = store.loadError { error=failure; return }
        let report=LedgerReport(store.book), selected=mode, include=share, search=web
        let previous = turns.filter { $0.mode == selected && (selected != .model || $0.shared == include) }.suffix(3)
        let id=UUID(); requestID=id; busy=true; error=nil; keyboard=false
        request = Task { @MainActor in
            defer { if requestID == id { busy=false; request=nil; requestID=nil } }
            do {
                let reply: AdvisorReply
                switch selected {
                case .ledger:
                    let followups = ["والشهر الماضي","والشهر السابق","وهذا الشهر","وامس","واليوم","والاسبوع الماضي"]
                    let isFollowup = followups.contains(Assistant.normalize(q).trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)))
                    var localQuestion = q
                    if isFollowup, let prior = previous.last, prior.reply.text.hasPrefix("إجمالي مصروفات") {
                        let category = Assistant.category(for: prior.question, history: report.book.entries)
                        localQuestion = "مصروفاتي " + (category == "أخرى" ? "" : (prior.question.components(separatedBy: " ").first { Assistant.category(for: $0, history: []) == category } ?? "")) + " " + q
                    }
                    if let value = report.answer(localQuestion) { reply = AdvisorReply(text:value,origin:"حساب من دفتر أمين") }
                    else if DeviceAdvisor.available {
                        let context = report.summary + "\n" + previous.suffix(1).map { String(($0.question+"\n"+$0.reply.text).prefix(1100)) }.joined()
                        reply = try await DeviceAdvisor.answer(q,context:context)
                    } else {
                        reply = AdvisorReply(text:"يمكنني حساب المصروفات والميزانية والديون والاستحقاقات من سجلك. جرّب «كم لي عند خالد؟». للأسئلة المفتوحة اختر النموذج السحابي، وللمعلومات المنشورة اختر المصادر العامة.",origin:"دليل أسئلة الدفتر")
                    }
                case .research: reply = try await AdvisorNetwork.live.research(q)
                case .model:
                    guard let key=AdvisorKey.read(), !key.isEmpty else { error="أضف مفتاحك من «إعداد مفتاح OpenAI» ثم أعد الإرسال."; return }
                    reply = try await AdvisorNetwork.live.cloud(question:q,previous:previous.map { ($0.question,$0.reply.text) },summary:include ? report.summary : nil,web:search,key:key)
                }
                try Task.checkCancellation()
                guard requestID == id else { return }
                turns.append(Exchange(question:q,reply:reply,mode:selected,shared:include))
                if turns.count > 30 { turns.removeFirst() }
                question=""; focusedAnswer=true
                UIAccessibility.post(notification:.announcement,argument:"وصلت إجابة أمين. " + reply.origin)
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                self.error=error.localizedDescription
                UIAccessibility.post(notification:.announcement,argument:error.localizedDescription)
            }
        }
    }
}
struct ModelSettings: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key=""
    @State private var exists=false
    @State private var status=""
    var body: some View {
        Form {
            Section {
                Text(exists ? "يوجد مفتاح محفوظ على هذا الآيفون." : "أضف مفتاح API من حساب OpenAI لتفعيل الاستشارات السحابية.")
                SecureField("مفتاح API الشخصي",text:$key).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("حفظ المفتاح") {
                    let clean=key.trimmingCharacters(in:.whitespacesAndNewlines)
                    guard !clean.isEmpty else { return }
                    if AdvisorKey.save(clean) { key=""; exists=true; status="تم الحفظ." } else { status="تعذّر حفظ المفتاح." }
                }.disabled(key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                if exists { Button("إزالة المفتاح من هذا الجهاز",role:.destructive) { if AdvisorKey.save("") { exists=false; key=""; status="تمت الإزالة." } else { status="تعذّرت الإزالة." } } }
                Link("إدارة مفاتيحي في OpenAI",destination:URL(string:"https://platform.openai.com/api-keys")!)
            } footer: { Text("يُحفظ المفتاح في سلسلة مفاتيح iOS ويُستخدم للاتصال المباشر بـ OpenAI. يُستبعد من نسخ الدفتر المصدّرة.") }
            if !status.isEmpty { Text(status) }
        }.navigationTitle("النموذج السحابي").onAppear { exists=AdvisorKey.read() != nil }
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("تم") { dismiss() } } }
    }
}

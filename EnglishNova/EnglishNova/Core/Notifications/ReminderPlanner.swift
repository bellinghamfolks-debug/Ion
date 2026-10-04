import Foundation

/// Plans the next two weeks of study reminders. The first one speaks to the
/// learner's real situation (streak at risk, reviews due, the next lesson);
/// later ones rotate short, varied nudges. Nothing is planned for a day the
/// learner has already studied, and reminders stop after two quiet weeks
/// instead of nagging forever.
enum ReminderPlanner {
    struct Context: Equatable {
        var hour: Int
        var minute: Int
        var studiedToday: Bool
        var streak: Int
        var dueReviews: Int
        var openMistakes: Int
        var nextLessonTitle: String?
    }

    struct Reminder: Equatable {
        let date: Date
        let title: String
        let body: String
    }

    static let horizonDays = 14

    static func plan(_ context: Context, now: Date = .now, calendar: Calendar = .current) -> [Reminder] {
        var reminders: [Reminder] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let fire = calendar.date(bySettingHour: context.hour, minute: context.minute, second: 0, of: day),
                  fire > now else { continue }
            if offset == 0 && context.studiedToday { continue }
            let text = reminders.isEmpty ? personalized(context) : rotating(index: offset)
            reminders.append(Reminder(date: fire, title: text.title, body: text.body))
        }
        return reminders
    }

    static func personalized(_ context: Context) -> (title: String, body: String) {
        if context.streak >= 2 {
            return (LfE("سلسلتك %@ أيام", "Your %@-day streak", "\(context.streak)"),
                    LE("جلسة قصيرة اليوم تحافظ عليها.", "A short session today keeps it going."))
        }
        if context.dueReviews > 0 {
            return (LE("حان وقت المراجعة", "Time to review"),
                    LfE("%@ عناصر تنتظر مراجعة سريعة قبل أن تُنسى.", "%@ items are ready for a quick review before they fade.", "\(context.dueReviews)"))
        }
        if context.openMistakes > 0 {
            return (LE("أخطاؤك تنتظرك", "Your mistakes are waiting"),
                    LfE("صحّح %@ أسئلة أخطأت فيها سابقًا.", "Fix %@ items you missed before.", "\(context.openMistakes)"))
        }
        if let title = context.nextLessonTitle, !title.isEmpty {
            return (LE("درسك التالي جاهز", "Your next lesson is ready"), title)
        }
        return rotating(index: 0)
    }

    static func rotating(index: Int) -> (title: String, body: String) {
        let options: [(String, String)] = [
            (LE("موعد إنجليزيتك اليوم", "Your English time"), LE("خمس دقائق تكفي لخطوة جديدة.", "Five minutes is enough for a new step.")),
            (LE("جلسة اليوم جاهزة", "Today's session is ready"), LE("مراجعة ودرس وتدريب قصير.", "A review, a lesson and a short practice.")),
            (LE("قل جملة بالإنجليزية", "Say a sentence in English"), LE("جرّب مدرّب النطق لدقيقتين.", "Try the pronunciation coach for two minutes.")),
            (LE("كلمة اليوم بانتظارك", "Your word of the day"), LE("تعلّم كلمة واحدة واستخدمها في جملة.", "Learn one word and use it in a sentence."))
        ]
        let item = options[abs(index) % options.count]
        return (item.0, item.1)
    }
}

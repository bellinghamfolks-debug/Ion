import XCTest

/// Walks through every screen of Basir and saves a screenshot of each.
///
/// Run by .github/workflows/basir-ios-screenshots.yml. The app is filled
/// with sample content by ScreenshotSeed (Debug builds only). Each step is
/// best effort: a screen that cannot be reached is skipped and the tour
/// continues, so one changed label never costs the whole set.
final class ScreenshotTour: XCTestCase {
    private var app: XCUIApplication!
    private var counter = 0

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: - The tour

    func test1_FirstLaunch() {
        launch(onboardingDone: false)
        shot("الترحيب ١")
        for page in 2...3 {
            tap(button: "التالي")
            shot("الترحيب \(arabic(page))")
        }
        tap(button: "ابدأ")
        pause(2.5)
        shot("أول شاشة بعد الترحيب")
    }

    func test2_NewTask() {
        launch()
        shotScrolling("جديد - تحويل إلى Word")
        scrollToTop()
        tap(button: "ترجمة")
        shotScrolling("جديد - ترجمة")
        tap(button: "تحويل إلى Word")

        for tool in ["صور إلى PDF", "قراءة فورية", "اسأل عن صورة", "قارن نسختين"] {
            scrollTo(tool)
            if tap(button: tool) {
                shotScrolling("أداة - \(tool)")
                close()
            }
        }
        scrollToTop()
        for source in ["ملف", "الصور"] {
            let tile = app.scrollViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", source)).firstMatch
            guard tile.waitForExistence(timeout: 3), tile.isHittable else { continue }
            tile.tap()
            pause(12)
            shot("مصدر - \(source)")
            close()
            scrollToTop()
        }
    }

    func test2b_VideoAndCurrency() {
        launch(extra: ["-video_launch_seen_v1", "NO"])
        pause(3)
        shotScrolling("فيديو - شاشة الإطلاق", limit: 2)
        if !tap(button: "لاحقًا") { dump("بعد لاحقًا") }
        pause(2)
        shot("فيديو - بعد إغلاق شاشة الإطلاق")
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "وصف الفيديو")).firstMatch
        for _ in 0..<6 where !(tile.exists && tile.isHittable) { app.swipeUp() }
        guard tile.waitForExistence(timeout: 5), tile.isHittable else {
            dump("لم يظهر زر وصف الفيديو")
            return
        }
        tile.tap()
        pause(2)
        shotScrolling("فيديو - الشاشة", limit: 3)
        scrollToTop()
        // The album must stay open until a video is chosen.
        if tap(button: "اختر فيديو من الألبوم") {
            pause(1)
            shot("فيديو - الألبوم بعد ثانية")
            pause(4)
            shot("فيديو - الألبوم بعد 5 ثوانٍ")
            dump("الألبوم")
            let firstVideo = app.images.firstMatch
            if firstVideo.waitForExistence(timeout: 5), firstVideo.isHittable {
                firstVideo.tap()
                pause(8)
                shot("فيديو - بعد اختيار فيديو")
            } else {
                close()
            }
        } else {
            dump("لم يظهر زر الألبوم")
        }
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 3) {
            field.tap()
            field.typeText("https://example.com/not-a-video")
            tap(button: "صِف الفيديو")
            pause(1)
            shot("فيديو - رابط غير صحيح")
        }
        // The described sample: its page, then watching with description.
        let sample = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "أرنب كبير")).firstMatch
        for _ in 0..<6 where !(sample.exists && sample.isHittable) { app.swipeUp() }
        if sample.exists && sample.isHittable {
            sample.tap()
            pause(2)
            shotScrolling("فيديو - الوصف", limit: 4)
            scrollToTop()
            if tap(button: "شاهد مع الوصف") {
                pause(10)
                shot("فيديو - المشاهدة مع الوصف")
                tap(button: "تشغيل")
                pause(12)
                shotScrolling("فيديو - أثناء التشغيل والوصف", limit: 2)
                close()
            } else {
                dump("لم يظهر زر المشاهدة")
            }
            if tap(button: "اسمع الوصف كاملًا") {
                pause(3)
                shot("فيديو - القارئ")
                close()
            }
            _ = back()
        } else {
            dump("لم يظهر الفيديو الموصوف")
        }
        close()
        pause(1)
        let currency = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "قارئ العملات")).firstMatch
        for _ in 0..<6 where !(currency.exists && currency.isHittable) { app.swipeUp() }
        if currency.exists && currency.isHittable {
            currency.tap()
            pause(4)
            shot("قارئ العملات")
            close()
        }
    }

    /// The screen's element tree, to see why a step could not be taken.
    private func dump(_ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "\(testPrefix)-عناصر \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        shot("عناصر - \(name)")
    }

    func test3_IncomingFile() {
        launch(extra: ["-BasirScreenshotIncoming"])
        pause(3)
        shot("ملف وارد من تطبيق آخر")
        tap(button: "تحويل إلى Word")
        pause(2)
        shotScrolling("جديد - ملف جاهز للتحويل")
    }

    func test4_MyFiles() {
        launch()
        tapTab("ملفاتي")
        shotScrolling("ملفاتي")
        if tap(button: "قراءة في بصير") {
            pause(3)
            shotScrolling("القارئ - الصفحة الأولى", limit: 3)
            for _ in 0..<2 where tap(button: "التالية") || tap(button: "الصفحة التالية") {
                pause(1)
                shotScrolling("القارئ - صفحة تالية", limit: 2)
            }
            exploreButtons(context: "القارئ", limit: 6)
            close()
        }
        tapTab("ملفاتي")
        if tap(button: "تقرير الجودة") {
            shotScrolling("تقرير الجودة")
            close()
        }
        if tap(button: "المزيد") {
            shot("ملفاتي - قائمة المزيد")
            app.tap()
            dismissMenu()
        }
        if tap(button: "معاينة") {
            pause(2)
            shot("معاينة الملف")
            close()
        }
    }

    func test5_Tasks() {
        launch()
        tapTab("المهام")
        shotScrolling("المهام")
        let names = ["دليل بصير التجريبي", "خطاب رسمي", "تقرير الصيانة السنوي", "فاتورة مصورة"]
        for name in names {
            tapTab("المهام")
            let row = element(containing: name)
            guard row.waitForExistence(timeout: 3) else { continue }
            row.tap()
            pause(2)
            let grabber = app.otherElements.matching(NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", "Grabber", "Grabber")).firstMatch
            if grabber.exists { grabber.swipeUp() } else { app.navigationBars.firstMatch.swipeUp() }
            pause(1.5)
            shotScrolling("مهمة - \(name)", limit: 3)
            close()
        }
    }

    func test6_Settings() {
        launch()
        guard openSettings() else { return }
        shotScrolling("الإعدادات")
        for link in ["خيارات متقدمة", "تواصل معنا", "عن بصير"] {
            scrollTo(link)
            guard tap(button: link) else { continue }
            pause(2)
            shotScrolling("الإعدادات - \(link)")
            if link == "عن بصير" {
                if tap(button: "الأسئلة الشائعة") {
                    pause(4)
                    shotScrolling("الأسئلة الشائعة", limit: 6)
                    back()
                }
                for external in ["الشروط والأحكام", "سياسة الخصوصية"] {
                    scrollTo(external)
                    if tap(button: external) {
                        pause(5)
                        shot(external)
                        returnToApp()
                    }
                }
            }
            back()
        }
    }

    func test7_DarkMode() {
        launch(extra: ["-interface_appearance", "dark"])
        shotScrolling("الوضع الداكن - جديد", limit: 2)
        tapTab("ملفاتي")
        shot("الوضع الداكن - ملفاتي")
        tapTab("المهام")
        shot("الوضع الداكن - المهام")
        if openSettings() { shotScrolling("الوضع الداكن - الإعدادات", limit: 2) }
    }

    // MARK: - Launching

    private func launch(onboardingDone: Bool = true, extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = [
            "-BasirScreenshotSeed",
            "-interface_language", "ar",
            "-AppleLanguages", "(ar)",
            "-AppleLocale", "ar_SA",
        ] + (onboardingDone ? ["-onboarding_completed_v3_1", "YES"] : []) + (extra.contains("-interface_appearance") ? [] : ["-interface_appearance", "light"])
          + (extra.contains("-video_launch_seen_v1") ? [] : ["-video_launch_seen_v1", "YES"]) + extra
        app.launch()
        pause(2)
        allowSystemAlerts()
    }

    private func allowSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["السماح", "Allow", "سماح"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1) { button.tap(); pause(1) }
        }
    }

    // MARK: - Screenshots

    private func shot(_ name: String) {
        dismissSystemTips()
        counter += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "%@-%02d %@", testPrefix, counter, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The screen, then each further screenful until the content stops moving.
    private func shotScrolling(_ name: String, limit: Int = 4) {
        shot(name)
        var previous = XCUIScreen.main.screenshot().pngRepresentation
        for index in 2...max(2, limit) {
            let scrollable = app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app.collectionViews.firstMatch
            guard scrollable.exists else { return }
            scrollable.swipeUp(velocity: .slow)
            pause(1)
            let current = XCUIScreen.main.screenshot().pngRepresentation
            if current == previous { break }
            shot("\(name) (\(arabic(index)))")
            previous = current
        }
        scrollToTop()
    }

    private var testPrefix: String {
        let name = String(describing: self)
        let match = name.range(of: #"test(\d)"#, options: .regularExpression)
        return match.map { String(name[$0].dropFirst(4)) } ?? "0"
    }

    // MARK: - Navigation helpers

    @discardableResult
    private func tap(button label: String, exact: Bool = false, timeout: TimeInterval = 3) -> Bool {
        let predicate = exact
            ? NSPredicate(format: "label == %@", label)
            : NSPredicate(format: "label BEGINSWITH %@", label)
        let candidates = [app.buttons.matching(predicate).firstMatch,
                          app.links.matching(predicate).firstMatch,
                          app.cells.matching(predicate).firstMatch]
        for candidate in candidates where candidate.waitForExistence(timeout: candidate == candidates[0] ? timeout : 0.5) {
            if candidate.isHittable {
                candidate.tap()
                pause(1.5)
                return true
            }
        }
        return false
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func tapTab(_ title: String) {
        let tab = app.tabBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        if tab.waitForExistence(timeout: 3) { tab.tap(); pause(1.5) }
    }

    private func openSettings() -> Bool {
        let gear = app.navigationBars.buttons["الإعدادات"].firstMatch
        guard gear.waitForExistence(timeout: 3) else { return false }
        gear.tap()
        pause(2)
        return true
    }

    private func scrollTo(_ label: String, upward: Bool = false) {
        let target = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        for _ in 0..<6 {
            if target.exists && target.isHittable { return }
            let scrollable = app.scrollViews.firstMatch
            guard scrollable.exists else { return }
            upward ? scrollable.swipeDown() : scrollable.swipeUp()
        }
    }

    /// Leaves a sheet, cover, or pushed screen.
    private func close() {
        for label in ["إغلاق", "تم", "إلغاء", "Cancel", "Done", "Close"] {
            let button = app.buttons[label].firstMatch
            if button.exists && button.isHittable { button.tap(); pause(1.5); return }
        }
        if back() { return }
        app.swipeDown(velocity: .fast)
        pause(1.5)
    }

    @discardableResult
    private func back() -> Bool {
        let button = app.navigationBars.buttons["BackButton"].firstMatch
        if button.exists, button.isHittable {
            button.tap()
            pause(1.5)
            return true
        }
        return false
    }

    /// Tapping the status bar scrolls to the top without ever dismissing a sheet.
    private func scrollToTop() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.012)).tap()
        pause(1.2)
    }

    /// The system's one-time keyboard tip covers half the screen.
    private func dismissSystemTips() {
        for label in ["Continue", "متابعة"] {
            let button = app.buttons[label].firstMatch
            if button.exists, button.isHittable { button.tap(); pause(1) }
        }
    }

    private func dismissMenu() {
        let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        outside.tap()
        pause(1)
    }

    private func returnToApp() {
        if app.state != .runningForeground {
            app.activate()
            pause(2)
        } else {
            close()
        }
    }

    /// Opens each new button on the current screen once and photographs what it shows.
    private func exploreButtons(context: String, limit: Int) {
        let skip = ["إغلاق", "تم", "حذف", "إلغاء", "مشاركة", "التالية", "السابقة", "الصفحة"]
        let labels = app.buttons.allElementsBoundByIndex
            .filter { $0.isHittable }
            .map(\.label)
            .filter { label in !label.isEmpty && !skip.contains { label.hasPrefix($0) } }
        for label in Array(Set(labels)).sorted().prefix(limit) {
            let before = XCUIScreen.main.screenshot().pngRepresentation
            guard tap(button: label, exact: true) else { continue }
            pause(1.5)
            if XCUIScreen.main.screenshot().pngRepresentation != before {
                shot("\(context) - \(label)")
                close()
            }
        }
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func arabic(_ number: Int) -> String {
        let digits = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
        return String(number).map { digits[Int(String($0))!] }.joined()
    }
}

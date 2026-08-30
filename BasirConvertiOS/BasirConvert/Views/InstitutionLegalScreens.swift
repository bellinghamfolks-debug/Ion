import SwiftUI
import Foundation

private struct BasirPublicSection: Decodable, Identifiable {
    let id: Int
    let title: String
    let body: String
}

private struct BasirPublicDocument: Decodable {
    let slug: String
    let language: String
    let title: String
    let updated: String
    let intro: String
    let sections: [BasirPublicSection]
}

struct ServerPublicDocumentView: View {
    let slug: String
    let isArabic: Bool

    @State private var document: BasirPublicDocument?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let document {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(document.title)
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)

                        Text((isArabic ? "آخر تحديث: " : "Last updated: ") + document.updated)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(document.intro)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(document.sections) { section in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(section.title)
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                                Text(section.body)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .contain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            } else if isLoading {
                ProgressView(isArabic ? "جاري تحميل المحتوى…" : "Loading content…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(isArabic ? "جاري تحميل المحتوى" : "Loading content")
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text(errorMessage ?? (isArabic ? "تعذر تحميل المحتوى." : "Unable to load content."))
                        .multilineTextAlignment(.center)
                    Button(isArabic ? "إعادة المحاولة" : "Try Again") {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(document?.title ?? fallbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(slug)-\(isArabic)") {
            await load()
        }
    }

    private var fallbackTitle: String {
        switch slug {
        case "terms": return isArabic ? "الشروط والأحكام" : "Terms and Conditions"
        case "privacy": return isArabic ? "سياسة الخصوصية" : "Privacy Policy"
        case "faq": return isArabic ? "الأسئلة المتكررة" : "Frequently Asked Questions"
        case "contact": return isArabic ? "التواصل" : "Contact"
        case "about": return isArabic ? "عن بصير" : "About Basir"
        default: return isArabic ? "بصير" : "Basir"
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        document = nil
        let language = isArabic ? "ar" : "en"
        guard var components = URLComponents(string: "https://basir-convert-api-1045442243599.europe-west4.run.app/api/public/content/\(slug)") else {
            isLoading = false
            errorMessage = isArabic ? "تعذر تجهيز عنوان المحتوى." : "Unable to prepare the content request."
            return
        }
        components.queryItems = [URLQueryItem(name: "lang", value: language)]
        guard let url = components.url else {
            isLoading = false
            errorMessage = isArabic ? "تعذر تجهيز عنوان المحتوى." : "Unable to prepare the content request."
            return
        }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(BasirPublicDocument.self, from: data)
            guard decoded.slug == slug else { throw URLError(.cannotParseResponse) }
            document = decoded
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = isArabic
                ? "تعذر تحميل المحتوى من بصير. تحقق من الاتصال وحاول مرة أخرى."
                : "Basir could not load this content. Check your connection and try again."
        }
    }
}


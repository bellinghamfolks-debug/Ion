import Foundation

@main enum ResearchCheck {
    static func main() async throws {
        let network = AdvisorNetwork.live
        for question in ["التضخم في السعودية", "الفائدة المركبة"] {
            let reply = try await network.research(question)
            guard !reply.sources.isEmpty, !reply.text.isEmpty else { throw AdvisorError.noSources }
            print("Retrieved:", reply.origin, reply.sources.compactMap { $0.url.host })
        }
    }
}

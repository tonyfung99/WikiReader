import Testing
import Foundation
@testable import WikiReader

@MainActor
struct AskHistoryStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "askhistorystore-tests-\(UUID().uuidString)")!
    }

    @Test func missingDataReturnsEmptyList() {
        let defaults = makeDefaults()
        #expect(AskHistoryStore.load(defaults: defaults).isEmpty)
    }

    @Test func savesAndLoadsRoundTrip() {
        let defaults = makeDefaults()
        let entries = [
            AskQueryEntry(question: "First", status: .done, save: true, submittedAt: Date(timeIntervalSince1970: 200)),
            AskQueryEntry(question: "Second", status: .running, save: false, submittedAt: Date(timeIntervalSince1970: 100)),
        ]
        AskHistoryStore.save(entries, defaults: defaults)
        let loaded = AskHistoryStore.load(defaults: defaults)
        #expect(Set(loaded.map(\.id)) == Set(entries.map(\.id)))
        #expect(loaded.count == 2)
    }

    @Test func loadSortsNewestFirstRegardlessOfSaveOrder() {
        let defaults = makeDefaults()
        let older = AskQueryEntry(question: "Older", save: false, submittedAt: Date(timeIntervalSince1970: 100))
        let newer = AskQueryEntry(question: "Newer", save: false, submittedAt: Date(timeIntervalSince1970: 200))
        AskHistoryStore.save([older, newer], defaults: defaults)
        let loaded = AskHistoryStore.load(defaults: defaults)
        #expect(loaded.map(\.question) == ["Newer", "Older"])
    }

    @Test func corruptDataReturnsEmptyList() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "askWiki.history")
        #expect(AskHistoryStore.load(defaults: defaults).isEmpty)
    }

    @Test func clearRemovesPersistedHistory() {
        let defaults = makeDefaults()
        AskHistoryStore.save([AskQueryEntry(question: "Q", save: true, submittedAt: Date())], defaults: defaults)
        AskHistoryStore.clear(defaults: defaults)
        #expect(AskHistoryStore.load(defaults: defaults).isEmpty)
    }
}

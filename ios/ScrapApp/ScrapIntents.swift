import AppIntents

struct ScrapTextIntent: AppIntent {
    static var title: LocalizedStringResource = "스크랩 텍스트 저장"
    static var description = IntentDescription("텍스트를 스크랩 도구에 저장합니다.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "텍스트")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "텍스트가 비어있습니다.")
        }
        let store = ScrapStore.shared
        store.load()
        store.addText(trimmed)
        let preview = String(trimmed.prefix(40)) + (trimmed.count > 40 ? "…" : "")
        return .result(dialog: "스크랩 완료: \(preview)")
    }
}

struct ScrapAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScrapTextIntent(),
            phrases: ["\(.applicationName) 클립보드 스크랩", "\(.applicationName) 스크랩"],
            shortTitle: "클립보드 스크랩",
            systemImageName: "doc.on.clipboard"
        )
    }
}

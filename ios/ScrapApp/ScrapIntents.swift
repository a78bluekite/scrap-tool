import AppIntents
import UIKit

struct ScrapClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "클립보드 스크랩"
    static var description = IntentDescription("클립보드의 텍스트를 스크랩 도구에 저장합니다.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return .result(dialog: "클립보드가 비어있습니다.")
        }
        let store = ScrapStore.shared
        store.load()
        store.addText(text)
        let preview = String(text.prefix(40)) + (text.count > 40 ? "…" : "")
        return .result(dialog: "스크랩 완료: \(preview)")
    }
}

struct ScrapAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScrapClipboardIntent(),
            phrases: ["클립보드 스크랩", "\(.applicationName) 스크랩"],
            shortTitle: "클립보드 스크랩",
            systemImageName: "doc.on.clipboard"
        )
    }
}

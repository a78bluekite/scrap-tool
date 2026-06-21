import UIKit
import SwiftUI
import UniformTypeIdentifiers

enum ShareExtractError: Error { case unavailable }

/// Principal class for the Share Extension. iOS shows this when the user taps
/// "Share" on selected text/images in any other app and picks this app.
class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task {
            let (text, image) = await extractInput()
            await MainActor.run {
                presentSwiftUI(text: text, image: image)
            }
        }
    }

    private func presentSwiftUI(text: String, image: UIImage?) {
        let root = ShareRootView(
            initialText: text,
            image: image,
            onCancel: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            },
            onSave: { [weak self] finalText, finalImage, folderId in
                ShareSaveHelper.save(text: finalText, image: finalImage, folderId: folderId)
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        )
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func extractInput() async -> (String, UIImage?) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return ("", nil) }
        var collectedText = ""
        var collectedImage: UIImage?

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let s = try? await loadText(provider, type: UTType.plainText.identifier), !s.isEmpty {
                        collectedText += (collectedText.isEmpty ? "" : "\n") + s
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await loadURL(provider) {
                        collectedText += (collectedText.isEmpty ? "" : "\n") + url.absoluteString
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let img = try? await loadImage(provider) {
                        collectedImage = img
                    }
                }
            }
        }

        if collectedText.isEmpty, let image = collectedImage {
            collectedText = await OCR.recognizeText(in: image)
        }

        return (collectedText, collectedImage)
    }

    private func loadText(_ provider: NSItemProvider, type: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { data, error in
                if let error { cont.resume(throwing: error); return }
                if let s = data as? String {
                    cont.resume(returning: s)
                } else if let d = data as? Data, let s = String(data: d, encoding: .utf8) {
                    cont.resume(returning: s)
                } else {
                    cont.resume(returning: "")
                }
            }
        }
    }

    private func loadURL(_ provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, error in
                if let error { cont.resume(throwing: error); return }
                if let url = data as? URL {
                    cont.resume(returning: url)
                } else {
                    cont.resume(throwing: ShareExtractError.unavailable)
                }
            }
        }
    }

    private func loadImage(_ provider: NSItemProvider) async throws -> UIImage {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { data, error in
                if let error { cont.resume(throwing: error); return }
                if let url = data as? URL, let img = UIImage(contentsOfFile: url.path) {
                    cont.resume(returning: img)
                } else if let img = data as? UIImage {
                    cont.resume(returning: img)
                } else if let d = data as? Data, let img = UIImage(data: d) {
                    cont.resume(returning: img)
                } else {
                    cont.resume(throwing: ShareExtractError.unavailable)
                }
            }
        }
    }
}

enum ShareSaveHelper {
    static func save(text: String, image: UIImage?, folderId: String) {
        let store = ScrapStore.shared
        store.load()
        if let image, let jpeg = image.jpegData(compressionQuality: 0.85) {
            store.addImage(jpeg, recognizedText: text, folderId: folderId)
        } else if !text.isEmpty {
            store.addText(text, folderId: folderId)
        }
    }
}

import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var store: ScrapStore
    @State private var showSettings    = false
    @State private var showAddText     = false
    @State private var showAddFolder   = false
    @State private var showFavorites   = false
    @State private var showCollect     = false
    @State private var showAIResult    = false
    @State private var showClearConfirm = false
    @State private var clipboardToast  = false
    @State private var aiTitle         = ""
    @State private var aiResult        = ""
    @State private var aiLoading       = false
    @State private var selectedFolderId: String = "default"
    @State private var photoItem: PhotosPickerItem?
    @State private var lastClipboardCount = UIPasteboard.general.changeCount
    @AppStorage("autoScrapClipboard") private var autoScrapClipboard = false

    var filteredItems: [ScrapItem] {
        store.items
            .filter { $0.folderId == selectedFolderId }
            .sorted { $0.order > $1.order }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                folderBar
                Divider()
                actionBar
                Divider()
                if filteredItems.isEmpty {
                    Spacer()
                    Text("아직 스크랩이 없습니다.\n위 버튼으로 추가하거나 다른 앱에서 공유하세요.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            ScrapRow(item: item)
                        }
                        .onDelete { idxSet in
                            for idx in idxSet { store.delete(filteredItems[idx]) }
                        }
                        .onMove { from, to in
                            store.move(filteredItems: filteredItems, from: from, to: to)
                        }
                    }
                    .listStyle(.plain)
                }
                Divider()
                bottomBar
            }
            .navigationTitle("✂ 스크랩 도구")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button { showFavorites = true } label: { Image(systemName: "star") }
                        EditButton()
                    }
                }
            }
            .overlay(alignment: .top) {
                if clipboardToast {
                    Text("클립보드 내용을 스크랩했습니다")
                        .font(.footnote)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: clipboardToast)
            .sheet(isPresented: $showSettings)    { SettingsView() }
            .sheet(isPresented: $showAddText)     { AddTextView(folderId: selectedFolderId) }
            .sheet(isPresented: $showAddFolder)   { AddFolderView() }
            .sheet(isPresented: $showFavorites)   { FavoritesView() }
            .sheet(isPresented: $showCollect)     { ResultView(title: "📋 취합 결과", content: collectText()) }
            .sheet(isPresented: $showAIResult)    { ResultView(title: aiTitle, content: aiResult) }
            .alert("폴더 비우기", isPresented: $showClearConfirm) {
                Button("삭제", role: .destructive) { clearCurrentFolder() }
                Button("취소", role: .cancel) {}
            } message: {
                let name = store.folders.first(where: { $0.id == selectedFolderId })?.name ?? "현재"
                Text("'\(name)' 폴더의 스크랩 \(filteredItems.count)개를 모두 삭제할까요?")
            }
            .task(id: photoItem) {
                guard let item = photoItem else { return }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    let text = await OCR.recognizeText(in: image)
                    if let jpeg = image.jpegData(compressionQuality: 0.85) {
                        store.addImage(jpeg, recognizedText: text, folderId: selectedFolderId)
                    }
                    photoItem = nil
                }
            }
            .onAppear {
                store.load()
                ensureSelectedFolderValid()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                store.load()
                ensureSelectedFolderValid()
                checkClipboardOnForeground()
            }
        }
    }

    // MARK: - 액션 버튼 바 (PC의 상단 버튼 행에 대응)

    private var actionBar: some View {
        HStack(spacing: 0) {
            // 클립보드 스크랩 — PC의 "선택 텍스트" 모드에 대응
            // iOS는 앱 간 드래그 감지가 불가하므로, 다른 앱에서 복사 후 이 버튼으로 스크랩
            actionBtn(icon: "doc.on.clipboard", label: "클립보드 스크랩") {
                scrapFromClipboard()
            }
            Divider().frame(height: 32)
            // 사진 가져오기 — PC의 "화면 캡처"에 대응
            PhotosPicker(selection: $photoItem, matching: .images) {
                VStack(spacing: 2) {
                    Image(systemName: "photo").font(.system(size: 15))
                    Text("사진 가져오기").font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            Divider().frame(height: 32)
            actionBtn(icon: "text.cursor", label: "텍스트 입력") {
                showAddText = true
            }
        }
        .frame(height: 50)
        .background(Color(.systemGray6))
    }

    private func actionBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 15))
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    // MARK: - 하단 AI 툴바

    private var bottomBar: some View {
        HStack(spacing: 0) {
            bottomBtn(icon: "doc.on.doc", label: "취합") {
                showCollect = true
            }
            Divider().frame(height: 36)
            bottomBtn(icon: "sparkles", label: "요약", loading: aiLoading) {
                doAI(mode: "summary")
            }
            Divider().frame(height: 36)
            bottomBtn(icon: "magnifyingglass", label: "분석", loading: aiLoading) {
                doAI(mode: "analysis")
            }
            Divider().frame(height: 36)
            bottomBtn(icon: "trash", label: "폴더 비우기") {
                if !filteredItems.isEmpty { showClearConfirm = true }
            }
        }
        .frame(height: 52)
        .background(Color(.systemBackground))
    }

    private func bottomBtn(icon: String, label: String, loading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if loading {
                    ProgressView().scaleEffect(0.75)
                } else {
                    Image(systemName: icon).font(.system(size: 16))
                }
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .disabled(loading)
    }

    // MARK: - 폴더 탭바

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(store.folders) { f in
                    Button(f.name) { selectedFolderId = f.id }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(f.id == selectedFolderId ? Color.accentColor : Color(.systemGray5))
                        .foregroundColor(f.id == selectedFolderId ? .white : .primary)
                        .clipShape(Capsule())
                }
                Button { showAddFolder = true } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 헬퍼

    private func ensureSelectedFolderValid() {
        if !store.folders.contains(where: { $0.id == selectedFolderId }) {
            selectedFolderId = store.folders.first?.id ?? "default"
        }
    }

    private func checkClipboardOnForeground() {
        let current = UIPasteboard.general.changeCount
        guard autoScrapClipboard, current != lastClipboardCount else { return }
        lastClipboardCount = current
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        store.addText(text, folderId: selectedFolderId)
        clipboardToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { clipboardToast = false }
    }

    private func scrapFromClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        store.addText(text, folderId: selectedFolderId)
        clipboardToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { clipboardToast = false }
    }

    private func clearCurrentFolder() {
        for item in filteredItems { store.delete(item) }
    }

    private func collectText() -> String {
        guard !filteredItems.isEmpty else { return "스크랩이 없습니다." }
        return filteredItems.enumerated().map { i, item in
            let type = item.type == .text ? "✍ 텍스트" : "📷 캡처"
            let ts   = item.timestamp.formatted(date: .abbreviated, time: .shortened)
            let body = item.text.isEmpty ? "[이미지 (텍스트 없음)]" : item.text
            return "────────────────────\n\(type)  #\(i+1)  \(ts)\n────────────────────\n\(body)"
        }.joined(separator: "\n\n")
    }

    private func allText() -> String {
        filteredItems.enumerated().compactMap { i, item in
            item.text.isEmpty ? nil : "[스크랩 \(i+1)]\n\(item.text)"
        }.joined(separator: "\n\n")
    }

    private func doAI(mode: String) {
        guard let key = Keychain.load(), !key.isEmpty else {
            aiTitle = "알림"; aiResult = "설정에서 Anthropic API 키를 먼저 등록하세요."
            showAIResult = true; return
        }
        let text = allText()
        guard !text.isEmpty else {
            aiTitle = "알림"; aiResult = "텍스트가 포함된 스크랩이 없습니다."
            showAIResult = true; return
        }
        aiLoading = true
        let prompt = mode == "summary"
            ? "다음 스크랩 텍스트를 핵심 내용 위주로 체계적으로 요약 정리해 주세요.\n\n\(text)"
            : "다음 스크랩 텍스트를 심층 분석해 주세요. 주제, 핵심 개념, 인사이트, 시사점을 포함해 주세요.\n\n\(text)"
        let title = mode == "summary" ? "✨ 요약 결과" : "🔍 분석 결과"
        Task {
            do {
                let result = try await ClaudeClient.send(prompt: prompt, apiKey: key)
                await MainActor.run {
                    aiTitle = title; aiResult = result; aiLoading = false; showAIResult = true
                }
            } catch {
                await MainActor.run {
                    aiTitle = "오류"; aiResult = error.localizedDescription; aiLoading = false; showAIResult = true
                }
            }
        }
    }
}

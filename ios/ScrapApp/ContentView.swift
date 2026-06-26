import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var store: ScrapStore
    @State private var showSettings = false
    @State private var showAddText = false
    @State private var showAddFolder = false
    @State private var showFavorites = false
    @State private var showCollect = false
    @State private var showAIResult = false
    @State private var showClearConfirm = false
    @State private var aiTitle = ""
    @State private var aiResult = ""
    @State private var aiLoading = false
    @State private var selectedFolderId: String = "default"

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
                if filteredItems.isEmpty {
                    Spacer()
                    Text("아직 스크랩이 없습니다.\n다른 앱에서 텍스트를 선택해 공유하거나,\n+ 버튼으로 직접 추가하세요.")
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
                        Button { showAddText = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showSettings)   { SettingsView() }
            .sheet(isPresented: $showAddText)    { AddTextView(folderId: selectedFolderId) }
            .sheet(isPresented: $showAddFolder)  { AddFolderView() }
            .sheet(isPresented: $showFavorites)  { FavoritesView() }
            .sheet(isPresented: $showCollect)    { ResultView(title: "📋 취합 결과", content: collectText()) }
            .sheet(isPresented: $showAIResult)   { ResultView(title: aiTitle, content: aiResult) }
            .alert("폴더 비우기", isPresented: $showClearConfirm) {
                Button("삭제", role: .destructive) { clearCurrentFolder() }
                Button("취소", role: .cancel) {}
            } message: {
                let name = store.folders.first(where: { $0.id == selectedFolderId })?.name ?? "현재"
                Text("'\(name)' 폴더의 스크랩 \(filteredItems.count)개를 모두 삭제할까요?")
            }
            .onAppear {
                store.load()
                ensureSelectedFolderValid()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                store.load()
                ensureSelectedFolderValid()
            }
        }
    }

    // MARK: - 하단 툴바

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

import SwiftUI
import UIKit

struct ScrapRow: View {
    @EnvironmentObject var store: ScrapStore
    let item: ScrapItem
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            HStack(alignment: .top, spacing: 10) {
                thumbnail
                VStack(alignment: .leading) {
                    Text(item.text.isEmpty ? "(이미지)" : item.text)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                    Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showDetail) {
            ScrapDetailView(item: item)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if item.type == .image, let url = store.image(for: item), let ui = UIImage(contentsOfFile: url.path) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "text.alignleft")
                .frame(width: 56, height: 56)
                .foregroundColor(.secondary)
        }
    }
}

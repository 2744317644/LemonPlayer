import SwiftUI

struct LibraryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("还没有媒体库", systemImage: "rectangle.stack.badge.play")
        } description: {
            Text("M5 接入 Bangumi 刮削后，这里会显示番剧海报墙。")
        }
        .navigationTitle("媒体库")
    }
}

#Preview {
    NavigationStack { LibraryView() }
}

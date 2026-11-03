import SwiftUI

struct PlayerView: View {
    let mediaTitle: String

    var body: some View {
        ContentUnavailableView {
            Label(mediaTitle, systemImage: "play.rectangle")
        } description: {
            Text("M3 接入播放内核后，这里会显示播放器与控制栏。")
        }
        .navigationTitle("播放")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { PlayerView(mediaTitle: "示例影片") }
}

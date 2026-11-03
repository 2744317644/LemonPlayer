import SwiftUI
import LemonPlayback
import LemonSubtitle

/// 演示播放：不依赖光鸭登录，用 Apple 公开 HLS 样例验证
/// 「AVPlayer 内核 + 自绘字幕 + 画中画/AirPlay + 动态字号」整条链路。
struct DemoPlayerView: View {
    @State private var engine = AVPlayerEngine()
    @State private var cues: [SubtitleCue] = []
    @State private var currentLine: String?
    @State private var showSubtitles = true
    @State private var isPlaying = true
    @State private var ticker: Task<Void, Never>?

    private static let streamURL = URL(
        string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8"
    )!

    private static let demoSRT = """
    1
    00:00:01,000 --> 00:00:06,000
    演示字幕：无需登录即可验证播放

    2
    00:00:06,000 --> 00:00:12,000
    这条字幕由自绘 overlay 渲染（可调样式）

    3
    00:00:12,000 --> 00:00:18,000
    MP4/HLS 走 AVPlayer，画中画与 AirPlay 可用

    4
    00:00:18,000 --> 00:00:26,000
    字幕字号会跟随系统辅助功能设置缩放
    """

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AVPlayerSurface(engine: engine)
                .ignoresSafeArea()

            VStack {
                Spacer()
                if showSubtitles, let currentLine {
                    SubtitleOverlayView(lines: [currentLine], style: .default)
                        .padding(.bottom, 64)
                }
            }

            VStack {
                Spacer()
                controlBar
            }
            .padding()
        }
        .navigationTitle("演示播放")
        .navigationBarTitleDisplayMode(.inline)
        .task { await start() }
        .onDisappear {
            ticker?.cancel()
            engine.stop()
        }
    }

    private var controlBar: some View {
        HStack(spacing: 18) {
            Button {
                isPlaying.toggle()
                if isPlaying { engine.play() } else { engine.pause() }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .accessibilityLabel(isPlaying ? "暂停" : "播放")

            Button {
                showSubtitles.toggle()
            } label: {
                Image(systemName: showSubtitles ? "captions.bubble.fill" : "captions.bubble")
                    .font(.title3)
            }
            .accessibilityLabel("字幕开关")

            AirPlayRouteView()
                .frame(width: 26, height: 26)

            if engine.isPiPAvailable {
                Button {
                    engine.togglePiP()
                } label: {
                    Image(systemName: "pip")
                        .font(.title3)
                }
                .accessibilityLabel("画中画")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.55))
        .clipShape(Capsule())
    }

    private func start() async {
        cues = SubtitleParser.parseCues(text: Self.demoSRT, format: .srt)
        do {
            try await engine.load(PlaybackSource(url: Self.streamURL, title: "演示"))
        } catch {
            return
        }
        isPlaying = true
        ticker = Task {
            while !Task.isCancelled {
                let time = engine.currentTime
                currentLine = cues.first { time >= $0.start && time < $0.end }?.text
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }
}

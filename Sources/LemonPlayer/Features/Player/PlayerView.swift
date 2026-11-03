import SwiftUI
import LemonGuangya
import LemonPlayback
import LemonSubtitle

struct PlayerView: View {
    private let files: [GuangyaFile]
    @State private var index: Int

    @Environment(SessionStore.self) private var session
    @State private var model: PlayerViewModel?

    init(file: GuangyaFile) {
        files = [file]
        _index = State(initialValue: 0)
    }

    init(files: [GuangyaFile], startIndex: Int = 0) {
        self.files = files
        _index = State(initialValue: min(max(0, startIndex), max(0, files.count - 1)))
    }

    private var currentFile: GuangyaFile? {
        guard files.indices.contains(index) else { return nil }
        return files[index]
    }

    var body: some View {
        Group {
            if let model {
                PlayerContent(model: model)
            } else {
                ProgressView("准备播放…")
            }
        }
        .navigationTitle(currentFile?.name ?? "播放")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: index) {
            model?.stop()
            model = nil
            guard let file = currentFile else { return }
            let created = PlayerViewModel(file: file, session: session)
            model = created
            await created.start()
        }
        .onChange(of: model?.didFinish) { _, finished in
            guard finished == true else { return }
            advanceToNextEpisode()
        }
        .onDisappear {
            model?.stop()
        }
    }

    private func advanceToNextEpisode() {
        guard index + 1 < files.count else { return }
        model?.stop()
        index += 1
    }
}

private struct PlayerContent: View {
    let model: PlayerViewModel
    @State private var showControls = true
    @State private var showStyleSheet = false
    @State private var isFullscreen = false
    @State private var hud: String?
    @State private var dragStartBrightness: Double?
    @State private var dragStartVolume: Float?

    private enum GestureSide {
        case brightness
        case volume
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VolumeControlView()
                .frame(width: 0, height: 0)

            surface

            if model.phase == .loading {
                ProgressView("获取播放地址…")
                    .tint(.white)
            }

            if case .failed(let message) = model.phase {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .font(.footnote)
                    Button("重试") {
                        Task { await model.retry() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
                .padding()
            }

            if model.phase == .ready {
                subtitleOverlay

                gestureLayer

                if let hud {
                    Text(hud)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.65))
                        .clipShape(Capsule())
                        .transition(.opacity)
                }

                controls
                    .opacity(showControls ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: showControls)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showControls.toggle()
        }
        .toolbar(isFullscreen ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(isFullscreen)
        .sheet(isPresented: $showStyleSheet) {
            SubtitleStyleSheet(style: model.subtitleStyle) { style in
                model.updateStyle(style)
            }
        }
    }

    private var gestureLayer: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    model.seek(to: max(0, model.currentTime - 10))
                }
                .gesture(verticalDrag(side: .brightness))
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    model.seek(to: min(model.duration, model.currentTime + 10))
                }
                .gesture(verticalDrag(side: .volume))
        }
    }

    private func verticalDrag(side: GestureSide) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                switch side {
                case .brightness:
                    if dragStartBrightness == nil {
                        dragStartBrightness = BrightnessController.value
                    }
                    let delta = -Double(value.translation.height) / 250
                    let next = min(max((dragStartBrightness ?? 0.5) + delta, 0), 1)
                    BrightnessController.set(next)
                    hud = "亮度 \(Int(next * 100))%"
                case .volume:
                    if dragStartVolume == nil {
                        dragStartVolume = VolumeController.shared.value
                    }
                    let delta = Float(-value.translation.height) / 250
                    let next = min(max((dragStartVolume ?? 0.5) + delta, 0), 1)
                    VolumeController.shared.set(next)
                    hud = "音量 \(Int(next * 100))%"
                }
            }
            .onEnded { _ in
                dragStartBrightness = nil
                dragStartVolume = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    withAnimation { hud = nil }
                }
            }
    }

    @ViewBuilder
    private var surface: some View {
        #if canImport(MobileVLCKit)
        if let engine = model.engine as? VLCKitEngine {
            VLCVideoSurface(engine: engine)
        } else {
            unsupportedSurface
        }
        #else
        unsupportedSurface
        #endif
    }

    private var unsupportedSurface: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.slash")
                .font(.largeTitle)
            Text("当前构建未包含播放内核（需要 CocoaPods + MobileVLCKit）")
                .font(.footnote)
                .multilineTextAlignment(.center)
            Text("状态：\(String(describing: model.engine.state))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding()
    }

    @ViewBuilder
    private var subtitleOverlay: some View {
        if model.isOverlaySubtitleActive, !model.activeSubtitleLines.isEmpty {
            VStack {
                Spacer()
                SubtitleOverlayView(lines: model.activeSubtitleLines, style: model.subtitleStyle)
                    .padding(.bottom, model.subtitleStyle.bottomInset)
            }
            .allowsHitTesting(false)
        }
    }

    private var controls: some View {
        VStack {
            Spacer()

            VStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { model.currentTime },
                        set: { model.seek(to: $0) }
                    ),
                    in: 0...max(model.duration, 1)
                )
                .tint(.yellow)

                HStack(spacing: 16) {
                    Button {
                        model.seek(to: max(0, model.currentTime - 10))
                    } label: {
                        Image(systemName: "gobackward.10")
                    }

                    Button {
                        model.togglePlay()
                    } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }

                    Button {
                        model.seek(to: min(model.duration, model.currentTime + 10))
                    } label: {
                        Image(systemName: "goforward.10")
                    }

                    Spacer()

                    Text("\(model.formattedPosition) / \(model.formattedDuration)")
                        .font(.caption.monospacedDigit())

                    subtitleMenu

                    Button {
                        showStyleSheet = true
                    } label: {
                        Image(systemName: "textformat.size")
                    }

                    Button {
                        toggleFullscreen()
                    } label: {
                        Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }

                    audioTrackMenu

                    Menu {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                            Button {
                                model.setRate(Float(value))
                            } label: {
                                if Float(value) == model.rate {
                                    Label("\(value, specifier: "%g")x", systemImage: "checkmark")
                                } else {
                                    Text("\(value, specifier: "%g")x")
                                }
                            }
                        }
                    } label: {
                        Text("\(Double(model.rate), specifier: "%g")x")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.white)
            }
            .padding()
            .background(.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()

            if let notice = model.subtitleNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.bottom, 8)
            }

            if let resume = model.resumeNotice {
                Text(resume)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 8)
            }
        }
    }

    private func toggleFullscreen() {
        withAnimation {
            isFullscreen.toggle()
        }
        OrientationManager.lock(to: isFullscreen ? .landscape : .portrait)
        showControls = !isFullscreen
    }

    private var audioTrackMenu: some View {
        Menu {
            ForEach(model.engine.audioTracks) { track in
                Button(track.name) {
                    model.engine.selectAudioTrack(id: track.id)
                }
            }
            if model.engine.audioTracks.isEmpty {
                Text("无音轨信息")
            }
        } label: {
            Image(systemName: "waveform")
        }
    }

    private var subtitleMenu: some View {
        Menu {
            Button("关闭字幕") {
                model.disableSubtitles()
            }
            Divider()
            Button("字幕延迟 +0.1s") {
                Task { await model.adjustSubtitleOffset(0.1) }
            }
            Button("字幕延迟 -0.1s") {
                Task { await model.adjustSubtitleOffset(-0.1) }
            }
            Button("重置延迟") {
                Task { await model.resetSubtitleOffset() }
            }
            Text("当前延迟 \(String(format: "%+.1f", model.subtitleOffsetValue))s")
            Divider()
            ForEach(model.subtitleCandidates) { candidate in
                Menu("\(candidate.fileName) · \(candidate.language.displayName)") {
                    Button("设为主字幕") {
                        Task { await model.attachCandidate(candidate) }
                    }
                    Button("设为副字幕") {
                        Task { await model.attachSecondary(candidate) }
                    }
                }
            }
            if model.subtitleCandidates.isEmpty {
                Text("同目录未找到字幕")
            }
        } label: {
            Image(systemName: model.attachedSubtitleName == nil ? "captions.bubble" : "captions.bubble.fill")
        }
    }
}

private struct SubtitleStyleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var style: SubtitleStyle
    private let onApply: (SubtitleStyle) -> Void

    init(style: SubtitleStyle, onApply: @escaping (SubtitleStyle) -> Void) {
        _style = State(initialValue: style)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("预览") {
                    ZStack {
                        Color.black
                        SubtitleOverlayView(
                            lines: ["示例字幕：这是预览效果 Sample"],
                            style: style
                        )
                        .padding(.vertical, 8)
                    }
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .listRowInsets(EdgeInsets())
                }

                Section("字号") {
                    HStack {
                        Slider(value: Binding(get: { style.fontSize }, set: { style.fontSize = $0; onApply(style) }), in: 14...40)
                        Text("\(Int(style.fontSize))")
                            .monospacedDigit()
                            .frame(width: 32)
                    }
                }

                Section("文字颜色") {
                    ColorPicker("颜色", selection: Binding(
                        get: { Color(hex: style.textColorHex) },
                        set: { style.textColorHex = $0.hexString; onApply(style) }
                    ))
                }

                Section("描边宽度") {
                    Slider(value: Binding(get: { style.outlineWidth }, set: { style.outlineWidth = $0; onApply(style) }), in: 0...5)
                }

                Section("背景不透明度") {
                    Slider(value: Binding(get: { style.backgroundOpacity }, set: { style.backgroundOpacity = $0; onApply(style) }), in: 0...0.9)
                }

                Section("底部边距") {
                    Slider(value: Binding(get: { style.bottomInset }, set: { style.bottomInset = $0; onApply(style) }), in: 20...240)
                }

                Section {
                    Button("恢复默认") {
                        style = .default
                        onApply(style)
                    }
                }
            }
            .navigationTitle("字幕样式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PlayerView(
            file: GuangyaFile(id: "1", parentID: "", name: "示例影片.mkv", size: 100, kind: .video)
        )
    }
    .environment(SessionStore())
}

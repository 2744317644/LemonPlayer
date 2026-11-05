import SwiftUI
import AVKit
import UniformTypeIdentifiers
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
                PlayerContent(model: model, title: currentFile?.name ?? "播放")
            } else {
                ProgressView("准备播放…")
            }
        }
        .navigationTitle(currentFile?.name ?? "播放")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let model: PlayerViewModel
    let title: String
    @State private var showControls = true
    @State private var showFontImporter = false
    @State private var activePanel: PlayerPanel?
    @State private var hud: String?
    @State private var dragStartBrightness: Double?
    @State private var dragStartVolume: Float?
    @State private var hideTask: Task<Void, Never>?

    enum PlayerPanel: String, Identifiable {
        case subtitles
        case audio
        case speed
        case style

        var id: String { rawValue }
    }

    private enum GestureSide {
        case brightness
        case volume
    }

    /// 左侧边缘右滑退出播放器（导航栏已隐藏，需要自己实现返回手势）。
    private var edgeSwipe: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onEnded { value in
                guard value.startLocation.x < 48, value.translation.width > 80 else { return }
                dismiss()
            }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VolumeControlView()
                .frame(width: 0, height: 0)

            surface
                .ignoresSafeArea()

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

                if let panel = activePanel {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            panelCard(panel)
                                .padding(.trailing, 18)
                                .padding(.bottom, 132)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if activePanel != nil {
                activePanel = nil
                return
            }
            withAnimation { showControls.toggle() }
            if showControls { scheduleHide() }
        }
        .onAppear {
            // 进入播放默认横屏（全屏）
            OrientationManager.lock(to: .landscape)
            scheduleHide()
        }
        .onDisappear {
            OrientationManager.lock(to: .portrait)
        }
        .onChange(of: model.isPlaying) { _, playing in
            if playing { scheduleHide() }
        }
        .onChange(of: scenePhase) { _, phase in
            // 退到后台自动暂停；回前台保持横屏（否则从桌面返回会变竖屏）
            if phase == .background {
                model.pauseForBackground()
            } else if phase == .active {
                OrientationManager.lock(to: .landscape)
            }
        }
        .simultaneousGesture(edgeSwipe)
        .fileImporter(
            isPresented: $showFontImporter,
            allowedContentTypes: [.font],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.importSubtitleFonts(urls)
            }
        }
    }

    private var gestureLayer: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    model.togglePlay()
                    showControls = true
                    scheduleHide()
                }
                .gesture(verticalDrag(side: .brightness))
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    model.togglePlay()
                    showControls = true
                    scheduleHide()
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
        if let engine = model.engine as? AVPlayerEngine {
            AVPlayerSurface(engine: engine)
        } else {
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
        VStack(spacing: 0) {
            topBar
            Spacer()
            centerPlayButton
            Spacer()
            bottomBar
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.7), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.62),
                    .init(color: .black.opacity(0.8), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .opacity(showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: showControls)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("返回")

            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            if model.isAVPlayerEngine {
                AirPlayRouteView()
                    .frame(width: 26, height: 26)

                if model.isPiPAvailable {
                    Button {
                        model.togglePiP()
                    } label: {
                        Image(systemName: "pip")
                            .font(.title3)
                    }
                    .accessibilityLabel("画中画")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var centerPlayButton: some View {
        Button {
            model.togglePlay()
            scheduleHide()
        } label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(.black.opacity(0.35))
                .clipShape(Circle())
        }
        .accessibilityLabel(model.isPlaying ? "暂停" : "播放")
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let notice = model.subtitleNotice {
                Text(notice)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            if let resume = model.resumeNotice {
                Text(resume)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Text(model.formattedPosition)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, alignment: .leading)

                PlayerProgressBar(
                    current: model.currentTime,
                    duration: model.duration,
                    onSeek: { value in
                        model.seek(to: value)
                        scheduleHide()
                    }
                )
                .frame(height: 22)

                Text(model.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, alignment: .trailing)
            }

            HStack(spacing: 26) {
                Spacer(minLength: 0)

                Button {
                    model.seek(to: max(0, model.currentTime - 10))
                    scheduleHide()
                } label: {
                    Image(systemName: "gobackward.10")
                }
                .accessibilityLabel("快退 10 秒")

                Button {
                    model.togglePlay()
                    scheduleHide()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(model.isPlaying ? "暂停" : "播放")

                Button {
                    model.seek(to: min(model.duration, model.currentTime + 10))
                    scheduleHide()
                } label: {
                    Image(systemName: "goforward.10")
                }
                .accessibilityLabel("快进 10 秒")

                Button {
                    activePanel = .speed
                    scheduleHide()
                } label: {
                    Text("\(Double(model.rate), specifier: "%g")x")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityLabel("播放速度")

                Button {
                    activePanel = .audio
                    scheduleHide()
                } label: {
                    Image(systemName: "waveform")
                }
                .accessibilityLabel("音轨")

                Button {
                    activePanel = .subtitles
                    scheduleHide()
                } label: {
                    Image(systemName: model.attachedSubtitleName == nil ? "captions.bubble" : "captions.bubble.fill")
                }
                .accessibilityLabel("字幕")

                Button {
                    activePanel = .style
                    scheduleHide()
                } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("字幕设置")

                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    // MARK: - 右侧弹出面板

    @ViewBuilder
    private func panelCard(_ panel: PlayerPanel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch panel {
            case .subtitles:
                subtitlePanel
            case .audio:
                audioPanel
            case .speed:
                speedPanel
            case .style:
                stylePanel
            }
        }
        .frame(width: 320, alignment: .leading)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }

    private var subtitlePanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            panelRowButton("关闭字幕") { model.disableSubtitles() }
            Divider().padding(.vertical, 4)
            panelRowButton("字幕延迟 -0.1s") { Task { await model.adjustSubtitleOffset(-0.1) } }
            panelRowButton("字幕延迟 +0.1s") { Task { await model.adjustSubtitleOffset(0.1) } }
            panelRowButton("重置延迟（当前 \(String(format: "%+.1f", model.subtitleOffsetValue))s）") {
                Task { await model.resetSubtitleOffset() }
            }
            Divider().padding(.vertical, 4)
            ForEach(model.subtitleCandidates) { candidate in
                HStack {
                    Text("\(candidate.fileName) · \(candidate.language.displayName)")
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Button("主") { Task { await model.attachCandidate(candidate) } }
                        .buttonStyle(.bordered)
                    Button("副") { Task { await model.attachSecondary(candidate) } }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            if model.subtitleCandidates.isEmpty {
                Text("同目录未找到字幕")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
            Divider().padding(.vertical, 4)
            panelRowButton("字幕设置（字号 / 边距）") { activePanel = .style }
            panelRowButton("导入 ASS 字体…") { showFontImporter = true }
        }
    }

    private var audioPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.engine.audioTracks) { track in
                panelRowButton(track.name) { model.engine.selectAudioTrack(id: track.id) }
            }
            if model.engine.audioTracks.isEmpty {
                Text("无音轨信息")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var speedPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                panelRowButton("\((value), specifier: "%g")x") {
                    model.setRate(Float(value))
                }
            }
        }
    }

    private var stylePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("字幕设置")
                .font(.headline)
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("字号")
                    Spacer()
                    Text("\(Int(model.subtitleStyle.fontSize))")
                        .monospacedDigit()
                }
                .font(.subheadline)
                Slider(
                    value: Binding(
                        get: { model.subtitleStyle.fontSize },
                        set: { newValue in
                            var style = model.subtitleStyle
                            style.fontSize = newValue
                            model.updateStyle(style)
                        }
                    ),
                    in: 14...40
                )
                .tint(.yellow)
            }
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("底部边距")
                    Spacer()
                    Text("\(Int(model.subtitleStyle.bottomInset))")
                        .monospacedDigit()
                }
                .font(.subheadline)
                Slider(
                    value: Binding(
                        get: { model.subtitleStyle.bottomInset },
                        set: { newValue in
                            var style = model.subtitleStyle
                            style.bottomInset = newValue
                            model.updateStyle(style)
                        }
                    ),
                    in: 0...240
                )
                .tint(.yellow)
            }
            .padding(.horizontal, 8)

            panelRowButton("恢复默认") {
                model.updateStyle(.default)
            }
        }
    }

    private func panelRowButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            scheduleHide()
        } label: {
            Text(title)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { showControls = false }
        }
    }

    private func toggleFullscreen() {
        // 播放器始终横屏，不再切竖屏
        OrientationManager.lock(to: .landscape)
    }


}

/// 自定义进度条：点击任意位置直接跳转，拖动实时预览。
private struct PlayerProgressBar: View {
    let current: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let total = max(duration, 1)
            let progress = min(max((dragValue ?? current) / total, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.25))
                    .frame(height: 4)

                Capsule()
                    .fill(.yellow)
                    .frame(width: width * progress, height: 4)

                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .offset(x: max(0, min(width - 16, width * progress - 8)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(value.location.x / width, 0), 1)
                        dragValue = fraction * total
                    }
                    .onEnded { value in
                        let fraction = min(max(value.location.x / width, 0), 1)
                        let target = fraction * total
                        dragValue = nil
                        onSeek(target)
                    }
            )
        }
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(Int(current)) / \(Int(duration)) 秒")
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

import SwiftUI
import AVKit
import UniformTypeIdentifiers
import LemonGuangya
import LemonMedia
import LemonPlayback
import LemonSubtitle

struct PlayerView: View {
    private let files: [GuangyaFile]
    private let demoSource: PlaybackSource?
    @State private var index: Int

    @Environment(SessionStore.self) private var session
    @State private var model: PlayerViewModel?

    init(file: GuangyaFile) {
        files = [file]
        demoSource = nil
        _index = State(initialValue: 0)
    }

    /// UI 测试/截图：直接进真实播放器界面（示例 HLS，不需要登录）。
    init(demoSource: PlaybackSource) {
        let displayName = demoSource.title.isEmpty ? "演示视频" : demoSource.title
        files = [GuangyaFile(id: "demo", parentID: "", name: displayName, size: 0, kind: .video)]
        self.demoSource = demoSource
        _index = State(initialValue: 0)
    }

    init(files: [GuangyaFile], startIndex: Int = 0) {
        self.files = files
        self.demoSource = nil
        _index = State(initialValue: min(max(0, startIndex), max(0, files.count - 1)))
    }

    private var currentFile: GuangyaFile? {
        guard files.indices.contains(index) else { return nil }
        return files[index]
    }

    var body: some View {
        Group {
            if let model {
                PlayerContent(
                    model: model,
                    title: currentFile?.name ?? "播放",
                    episodes: files,
                    currentIndex: index,
                    onSelectEpisode: { selected in
                        guard selected != index, files.indices.contains(selected) else { return }
                        model.stop()
                        index = selected
                    }
                )
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
            let created = PlayerViewModel(file: file, session: session, demoSource: demoSource)
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
    let episodes: [GuangyaFile]
    let currentIndex: Int
    let onSelectEpisode: (Int) -> Void
    @State private var showControls = true
    @State private var isLocked = false
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
        case episodes
        case more

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
                guard !isLocked,
                      value.startLocation.x < 48,
                      value.translation.width > 80 else { return }
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
                if isLocked {
                    lockOverlay
                } else {
                    subtitleOverlay

                    gestureLayer

                    if model.isBuffering {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.3)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: model.isBuffering)
                    }

                    if let hud {
                        Text(hud)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.65))
                            .clipShape(Capsule())
                            .transition(.opacity)
                            .animation(.easeOut(duration: 0.15), value: hud)
                    }

                    controls
                        .opacity(showControls ? 1 : 0)
                        .allowsHitTesting(showControls)
                        .animation(.easeInOut(duration: 0.2), value: showControls)

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
                        .animation(.easeOut(duration: 0.18), value: activePanel)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onAppear {
            // 进入播放默认横屏（全屏）
            OrientationManager.lock(to: .landscape)
            scheduleHide()
        }
        .onDisappear {
            OrientationManager.lock(to: .portrait)
        }
        .onChange(of: model.isPlaying) { _, playing in
            if playing, activePanel == nil { scheduleHide() }
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

    /// 锁屏后只保留解锁按钮（VidHub 左侧锁屏）。
    private var lockOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Button {
                    withAnimation { isLocked = false; showControls = true }
                    scheduleHide()
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .accessibilityLabel("解锁屏幕")
                .padding(.leading, 18)
                Spacer()
            }
            Spacer()
        }
    }

    private var gestureLayer: some View {
        HStack(spacing: 0) {
            // 左侧双击快退 + 上下滑动亮度
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(tapZone {
                    flashHUD("快退 10 秒")
                    model.seek(to: max(0, model.currentTime - 10))
                    scheduleHide()
                })
                .gesture(verticalDrag(side: .brightness))
            // 中间双击播放/暂停
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(tapZone {
                    model.togglePlay()
                    showControls = true
                    scheduleHide()
                })
            // 右侧双击快进 + 上下滑动音量
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(tapZone {
                    flashHUD("快进 10 秒")
                    model.seek(to: min(model.duration, model.currentTime + 10))
                    scheduleHide()
                })
                .gesture(verticalDrag(side: .volume))
        }
    }

    /// VidHub 手势：双击执行 doubleTap，单击显示/隐藏控制层。
    private func tapZone(doubleTap: @escaping () -> Void) -> some Gesture {
        ExclusiveGesture(TapGesture(count: 2), TapGesture())
            .onEnded { value in
                switch value {
                case .first:
                    doubleTap()
                case .second:
                    handleSurfaceTap()
                }
            }
    }

    private func handleSurfaceTap() {
        if activePanel != nil {
            withAnimation { activePanel = nil }
            scheduleHide()
            return
        }
        withAnimation { showControls.toggle() }
        if showControls { scheduleHide() }
    }

    private func openPanel(_ panel: PlayerPanel) {
        hideTask?.cancel()
        withAnimation { activePanel = panel }
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
        ZStack {
            VStack(spacing: 0) {
                topBar
                Spacer()
                if !model.isPlaying {
                    centerPlayButton
                }
                Spacer()
                bottomBar
            }

            HStack {
                sideControls
                Spacer()
            }
            .padding(.leading, 18)
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
        .animation(.easeInOut(duration: 0.2), value: model.isPlaying)
    }

    /// 左侧竖排（VidHub）：锁屏、选集。
    private var sideControls: some View {
        VStack(spacing: 22) {
            Button {
                withAnimation { isLocked = true; showControls = false; activePanel = nil }
            } label: {
                Image(systemName: "lock.open")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.28), in: Circle())
            }
            .accessibilityLabel("锁定屏幕")

            if episodes.count > 1 {
                Button {
                    openPanel(.episodes)
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.28), in: Circle())
                }
                .accessibilityLabel("选集")
            }
        }
    }

    private var topBar: some View {
        ZStack {
            HStack(spacing: 14) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("返回")

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

                Button {
                    openPanel(.more)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("更多")
            }

            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 80)
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
                .frame(height: 34)

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
                    openPanel(.speed)
                } label: {
                    Text("\(Double(model.rate), specifier: "%g")x")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityLabel("播放速度")

                Button {
                    openPanel(.audio)
                } label: {
                    Image(systemName: "waveform")
                }
                .accessibilityLabel("音轨")

                Button {
                    openPanel(.subtitles)
                } label: {
                    Image(systemName: model.attachedSubtitleName == nil ? "captions.bubble" : "captions.bubble.fill")
                }
                .accessibilityLabel("字幕")

                Button {
                    openPanel(.style)
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
            case .episodes:
                episodesPanel
            case .more:
                morePanel
            }
        }
        .frame(width: 320, alignment: .leading)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }

    /// 右上角更多（VidHub 的「三个点」）。
    private var morePanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("更多")
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            if episodes.count > 1 {
                panelRowButton("选集（\(currentIndex + 1)/\(episodes.count)）") { openPanel(.episodes) }
            }
            panelRowButton("字幕") { openPanel(.subtitles) }
            panelRowButton("音轨") { openPanel(.audio) }
            panelRowButton("播放速度") { openPanel(.speed) }
            panelRowButton("字幕设置") { openPanel(.style) }
            Divider().padding(.vertical, 4)
            panelRowButton("锁定屏幕") {
                withAnimation {
                    isLocked = true
                    showControls = false
                    activePanel = nil
                }
            }
        }
    }

    /// 双击快进/快退时短暂显示提示。
    private func flashHUD(_ text: String) {
        hud = text
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            if hud == text { hud = nil }
        }
    }

    /// 同文件夹选集（VidHub 左侧选集）。
    private var episodesPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("选集（\(currentIndex + 1)/\(episodes.count)）")
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(episodes.enumerated()), id: \.offset) { offset, episode in
                        Button {
                            activePanel = nil
                            onSelectEpisode(offset)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: offset == currentIndex ? "play.circle.fill" : "circle")
                                    .font(.footnote)
                                Text(SeriesFolderResolver.cleanTitle(episode.name))
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private var subtitlePanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.attachedSubtitleName.map { "当前：\($0)" } ?? "当前：关闭")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)

            panelRowButton("关闭字幕") { model.disableSubtitles() }
            panelRowButton("重新匹配同目录字幕") { Task { await model.autoAttachSubtitle() } }
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
            panelRowButton("字幕设置（字号 / 边距）") { openPanel(.style) }
            panelRowButton("导入 ASS 字体…") { showFontImporter = true }
            if SubtitleFontStore.count > 0 {
                Text("已导入字体 \(SubtitleFontStore.count) 个（重播生效）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
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
                panelRowButton(String(format: "%gx", value)) {
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
            .highPriorityGesture(
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


#Preview {
    NavigationStack {
        PlayerView(
            file: GuangyaFile(id: "1", parentID: "", name: "示例影片.mkv", size: 100, kind: .video)
        )
    }
    .environment(SessionStore())
}

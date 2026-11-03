import SwiftUI
import LemonGuangya
import LemonMedia
import LemonPersistence

struct LibraryView: View {
    @Environment(SessionStore.self) private var session
    @State private var model: LibraryViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("媒体库")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model?.scan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model?.phase == .scanning)
            }
        }
        .task {
            guard model == nil else { return }
            let created = LibraryViewModel(session: session)
            model = created
            await created.loadCached()
        }
        .onAppear {
            Task { await model?.loadRecent() }
        }
    }

    @ViewBuilder
    private func content(_ model: LibraryViewModel) -> some View {
        switch model.phase {
        case .idle, .loaded:
            libraryContent(model)

        case .scanning:
            VStack(spacing: 12) {
                ProgressView()
                Text(model.statusMessage ?? "扫描中…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .failed(let message):
            ContentUnavailableView {
                Label("扫描失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重试") {
                    Task { await model.scan() }
                }
            }
        }
    }

    private func libraryContent(_ model: LibraryViewModel) -> some View {
        ScrollView {
            if !model.recent.isEmpty {
                recentSection(model)
            }

            if model.series.isEmpty {
                VStack(spacing: 14) {
                    ContentUnavailableView {
                        Label("还没有媒体库", systemImage: "rectangle.stack.badge.play")
                    } description: {
                        Text("扫描光鸭云盘中的视频，按 Bangumi 自动匹配番剧海报与剧集。")
                    }
                    Button("扫描网盘") {
                        Task { await model.scan() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 24)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 12)], spacing: 16) {
                    ForEach(model.series) { series in
                        NavigationLink {
                            SeriesDetailView(series: series)
                        } label: {
                            posterCard(series)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }

    private func recentSection(_ model: LibraryViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("继续观看")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.recent.filter { $0.fileName != nil }, id: \.fileID) { progress in
                        NavigationLink {
                            PlayerView(file: makeFile(from: progress))
                        } label: {
                            recentCard(progress)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
    }

    private func recentCard(_ progress: PlaybackProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 160, height: 90)
                .overlay(
                    Image(systemName: "play.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                )

            Text(progress.fileName ?? "未知文件")
                .font(.caption)
                .lineLimit(1)

            ProgressView(value: progress.progressFraction)
                .tint(.yellow)
        }
        .frame(width: 160)
    }

    private func makeFile(from progress: PlaybackProgress) -> GuangyaFile {
        GuangyaFile(
            id: progress.fileID,
            parentID: progress.parentID ?? "",
            name: progress.fileName ?? "",
            size: 0,
            kind: .video
        )
    }

    private func posterCard(_ series: LibrarySeries) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            posterImage(series)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(series.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text("\(series.episodes.count) 集")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func posterImage(_ series: LibrarySeries) -> some View {
        if let raw = series.coverURL, let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

struct SeriesDetailView: View {
    let series: LibrarySeries
    @State private var queue: [GuangyaFile] = []
    @State private var startIndex = 0
    @State private var showPlayer = false

    private var sortedEpisodes: [SeriesEpisode] {
        series.episodes
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    poster
                        .frame(width: 88, height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(series.title)
                            .font(.headline)
                        if let year = series.year {
                            Text(String(year))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let score = series.score {
                            Label(String(format: "%.1f", score), systemImage: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                        Text("\(series.episodes.count) 集")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("剧集") {
                ForEach(Array(sortedEpisodes.enumerated()), id: \.element.id) { offset, episode in
                    Button {
                        play(from: offset)
                    } label: {
                        HStack {
                            Text(episode.displayName)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "play.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showPlayer) {
            PlayerView(files: queue, startIndex: startIndex)
        }
    }

    private func play(from offset: Int) {
        queue = sortedEpisodes.map {
            GuangyaFile(
                id: $0.id,
                parentID: $0.parentID,
                name: $0.fileName,
                size: 0,
                kind: .video
            )
        }
        startIndex = offset
        showPlayer = true
    }

    @ViewBuilder
    private var poster: some View {
        if let raw = series.coverURL, let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable()
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
        } else {
            Color.secondary.opacity(0.15)
        }
    }
}

#Preview {
    NavigationStack { LibraryView() }
        .environment(SessionStore())
}

import SwiftUI
import LemonGuangya
import LemonMedia

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
    }

    @ViewBuilder
    private func content(_ model: LibraryViewModel) -> some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView {
                Label("还没有媒体库", systemImage: "rectangle.stack.badge.play")
            } description: {
                Text("扫描光鸭云盘中的视频，按 Bangumi 自动匹配番剧海报与剧集。")
            } actions: {
                Button("扫描网盘") {
                    Task { await model.scan() }
                }
                .buttonStyle(.borderedProminent)
            }

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

        case .loaded:
            if model.series.isEmpty {
                ContentUnavailableView("没有可展示的系列", systemImage: "film.stack")
            } else {
                grid(model)
            }
        }
    }

    private func grid(_ model: LibraryViewModel) -> some View {
        ScrollView {
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
    @State private var playing: GuangyaFile?

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
                ForEach(series.episodes) { episode in
                    Button {
                        playing = GuangyaFile(
                            id: episode.id,
                            parentID: episode.parentID,
                            name: episode.fileName,
                            size: 0,
                            kind: .video
                        )
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
        .navigationDestination(item: $playing) { file in
            PlayerView(file: file)
        }
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

import SwiftUI
import LemonGuangya
import LemonMedia
import LemonPersistence

/// iPad（regular 宽度）媒体库分栏：左侧番剧与继续观看，右侧详情/播放。
struct LibrarySplitView: View {
    @Environment(SessionStore.self) private var session
    @State private var model: LibraryViewModel?
    @State private var selection: Selection?

    enum Selection: Hashable {
        case series(String)
        case recent(String)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
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
        } detail: {
            detail
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
    private var sidebar: some View {
        if let model {
            switch model.phase {
            case .scanning:
                VStack(spacing: 10) {
                    ProgressView()
                    Text(model.statusMessage ?? "扫描中…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("取消扫描", role: .cancel) { model.cancelScan() }
                }

            case .failed(let message):
                ContentUnavailableView {
                    Label("扫描失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") { Task { await model.scan() } }
                }

            case .idle, .loaded:
                List {
                    if !recentItems(model).isEmpty {
                        Section("继续观看") {
                            ForEach(recentItems(model), id: \.fileID) { progress in
                                Button {
                                    selection = .recent(progress.fileID)
                                } label: {
                                    recentRow(progress)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Section("番剧（\(model.series.count)）") {
                        if model.series.isEmpty {
                            Button("扫描网盘") {
                                Task { await model.scan() }
                            }
                        } else {
                            ForEach(model.series) { series in
                                Button {
                                    selection = .series(series.id)
                                } label: {
                                    seriesRow(series)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let model {
            switch selection {
            case .series(let id):
                if let series = model.series.first(where: { $0.id == id }) {
                    NavigationStack {
                        SeriesDetailView(series: series)
                    }
                } else {
                    placeholder
                }
            case .recent(let fileID):
                if let progress = model.recent.first(where: { $0.fileID == fileID }) {
                    NavigationStack {
                        PlayerView(file: makeFile(from: progress))
                    }
                } else {
                    placeholder
                }
            case nil:
                placeholder
            }
        } else {
            ProgressView()
        }
    }

    private var placeholder: some View {
        ContentUnavailableView {
            Label("选择一个番剧", systemImage: "rectangle.stack")
        } description: {
            Text("从左侧选择番剧查看剧集，或选择「继续观看」直接播放。")
        }
    }

    private func recentItems(_ model: LibraryViewModel) -> [PlaybackProgress] {
        model.recent.filter { $0.fileName != nil }
    }

    private func recentRow(_ progress: PlaybackProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(progress.fileName ?? "未知视频")
                .lineLimit(1)
            ProgressView(value: progress.progressFraction)
                .tint(.yellow)
        }
        .padding(.vertical, 2)
    }

    private func seriesRow(_ series: LibrarySeries) -> some View {
        HStack(spacing: 10) {
            poster(for: series)
                .frame(width: 38, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(series.title)
                    .lineLimit(1)
                Text("\(series.episodes.count) 集" + (series.year.map { " · \($0)" } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func poster(for series: LibrarySeries) -> some View {
        if let raw = series.coverURL, let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
        } else {
            Color.secondary.opacity(0.2)
                .overlay(Image(systemName: "film").foregroundStyle(.secondary))
        }
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
}

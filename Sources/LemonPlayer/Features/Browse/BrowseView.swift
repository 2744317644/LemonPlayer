import SwiftUI
import LemonGuangya

struct BrowseView: View {
    @Environment(SessionStore.self) private var session
    @State private var model: BrowseViewModel?
    @State private var playing: GuangyaFile?

    var body: some View {
        Group {
            if let model {
                BrowseContent(model: model, playing: $playing)
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                model = BrowseViewModel(session: session)
            }
            await model?.start()
        }
        .navigationDestination(item: $playing) { file in
            PlayerView(mediaTitle: file.name)
        }
    }
}

private struct BrowseContent: View {
    let model: BrowseViewModel
    @Binding var playing: GuangyaFile?

    var body: some View {
        List {
            if model.canGoUp {
                Button {
                    Task { await model.goUp() }
                } label: {
                    Label("返回上一级", systemImage: "arrow.up.left")
                }
            }

            ForEach(model.items) { file in
                Button {
                    open(file)
                } label: {
                    row(for: file)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if file.id == model.items.last?.id {
                        Task { await model.loadMore() }
                    }
                }
            }

            if model.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            switch model.phase {
            case .loading:
                HStack {
                    Spacer()
                    ProgressView("加载中…")
                    Spacer()
                }
            case .failed(let message):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await model.reload() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
            case .loaded where model.items.isEmpty:
                ContentUnavailableView("空目录", systemImage: "folder", description: Text("这个目录里没有文件"))
            default:
                EmptyView()
            }
        }
        .refreshable { await model.reload() }
        .navigationTitle(model.currentFolderName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(BrowseViewModel.SortOption.allCases) { option in
                        Button {
                            Task { await model.changeSort(option) }
                        } label: {
                            if option == model.sort {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    private func open(_ file: GuangyaFile) {
        if file.isFolder {
            Task { await model.enter(file) }
        } else if file.isPlayable {
            playing = file
        }
    }

    private func row(for file: GuangyaFile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: file))
                .font(.title3)
                .foregroundStyle(file.isFolder ? Color.yellow : Color.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Formatters.subtitle(for: file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if file.isFolder {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func icon(for file: GuangyaFile) -> String {
        switch file.kind {
        case .folder: return "folder.fill"
        case .video: return "film"
        case .audio: return "music.note"
        case .image: return "photo"
        case .document: return "doc.text"
        case .archive: return "archivebox"
        case .torrent: return "link"
        case .other: return "doc"
        }
    }
}

#Preview {
    NavigationStack { BrowseView() }
        .environment(SessionStore())
}

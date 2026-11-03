import SwiftUI
import LemonDownloads

struct DownloadsView: View {
    @State private var model: DownloadsViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("下载")
        .task {
            guard model == nil else { return }
            let created = DownloadsViewModel()
            model = created
            await created.start()
        }
    }

    @ViewBuilder
    private func content(_ model: DownloadsViewModel) -> some View {
        if model.records.isEmpty {
            ContentUnavailableView {
                Label("还没有下载", systemImage: "arrow.down.circle")
            } description: {
                Text("在网盘文件上长按 → 选择「下载」，即可离线播放。")
            }
        } else {
            List {
                Section {
                    LabeledContent("已下载", value: Formatters.fileSize(model.totalDownloadedBytes))
                }

                Section("任务") {
                    ForEach(model.records) { record in
                        row(record, model: model)
                    }
                    .onDelete { offsets in
                        model.remove(at: offsets)
                    }
                }
            }
        }
    }

    private func row(_ record: DownloadRecord, model: DownloadsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(record.fileName)
                    .lineLimit(1)
                Spacer()
                Text(record.stateText)
                    .font(.caption)
                    .foregroundStyle(record.state == .failed ? .red : .secondary)
            }

            if record.state == .downloading || record.state == .paused {
                ProgressView(value: record.progressFraction)
                    .tint(.yellow)
                HStack {
                    Text(Formatters.fileSize(record.downloadedBytes))
                    Text("/")
                    Text(Formatters.fileSize(record.totalBytes))
                    Spacer()
                    Text("\(Int(record.progressFraction * 100))%")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if let error = record.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 16) {
                switch record.state {
                case .downloading:
                    Button("暂停") { model.pause(record) }
                case .paused, .failed:
                    Button("继续") { model.resume(record) }
                case .queued:
                    Button("取消") { model.cancel(record) }
                default:
                    EmptyView()
                }
                Button("删除", role: .destructive) { model.remove(record) }
                Spacer()
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { DownloadsView() }
}

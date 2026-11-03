import SwiftUI
import UIKit
import LemonCore

struct DiagnosticsView: View {
    @State private var entries: [DiagnosticEntry] = []
    @State private var exportURL: URL?
    @State private var showShare = false

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("暂无日志", systemImage: "doc.text.magnifyingglass", description: Text("操作 App 后会在这里记录关键事件（已脱敏）。"))
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.level.rawValue.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(color(for: entry.level))
                            Text(entry.category)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.caption.monospaced())
                            .lineLimit(3)
                    }
                }
            }
        }
        .navigationTitle("诊断日志")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        exportURL = await DiagnosticsCenter.shared.exportFile()
                        showShare = exportURL != nil
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空", role: .destructive) {
                    Task {
                        await DiagnosticsCenter.shared.clear()
                        entries = await DiagnosticsCenter.shared.recent(limit: 200)
                    }
                }
            }
        }
        .task { await reload() }
        .sheet(isPresented: $showShare) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
    }

    private func reload() async {
        let list = await DiagnosticsCenter.shared.recent(limit: 200)
        entries = Array(list.reversed())
    }

    private func color(for level: DiagnosticLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

import SwiftUI
import UIKit
import LemonCore

struct DiagnosticsView: View {
    @State private var entries: [DiagnosticEntry] = []
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case errors = "错误"
        case warnings = "警告"

        var id: String { rawValue }
    }

    private var filteredEntries: [DiagnosticEntry] {
        switch filter {
        case .all: return entries
        case .errors: return entries.filter { $0.level.rawValue == "error" }
        case .warnings: return entries.filter { $0.level.rawValue == "warning" }
        }
    }

    var body: some View {
        List {
            Section("概览") {
                LabeledContent("日志", value: "\(entries.count) 条")
                LabeledContent("错误", value: "\(entries.filter { $0.level.rawValue == "error" }.count) 条")
                LabeledContent("启动耗时", value: AppMetrics.launchText)
                LabeledContent("内存占用", value: AppMetrics.memoryText)
                Button("复制最近错误") {
                    Task {
                        let list = await DiagnosticsCenter.shared.recent(limit: 200)
                        let body = list
                            .filter { $0.level.rawValue == "error" }
                            .map { "[\($0.category)] \($0.message)" }
                            .joined(separator: "\n")
                        UIPasteboard.general.string = metadataHeader() + "\n\n" + body
                    }
                }
            }

            Picker("筛选", selection: $filter) {
                ForEach(Filter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            if filteredEntries.isEmpty {
                ContentUnavailableView("暂无日志", systemImage: "doc.text.magnifyingglass", description: Text("操作 App 后会在这里记录关键事件（已脱敏）。"))
            } else {
                ForEach(filteredEntries) { entry in
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
                        exportURL = await DiagnosticsCenter.shared.exportFile(header: metadataHeader())
                        showShare = exportURL != nil
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        let body = await DiagnosticsCenter.shared.summary(limit: 100)
                        UIPasteboard.general.string = metadataHeader() + "\n\n" + body
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("复制诊断摘要")
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

    private func metadataHeader() -> String {
        let device = UIDevice.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return """
        App: LemonPlayer \(LemonCore.version) (\(LemonCore.build))
        System: \(device.systemName) \(device.systemVersion)
        Device: \(device.model) / \(device.machineIdentifier)
        Time: \(formatter.string(from: Date()))
        Launch: \(AppMetrics.launchText)
        Memory: \(AppMetrics.memoryText)
        """
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

private extension UIDevice {
    var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

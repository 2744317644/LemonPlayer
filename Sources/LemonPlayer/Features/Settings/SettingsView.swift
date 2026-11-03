import SwiftUI
import LemonCore

struct SettingsView: View {
    var body: some View {
        Form {
            Section("关于") {
                LabeledContent("版本", value: LemonCore.version)
                LabeledContent("构建", value: LemonCore.build)
            }

            Section("账号") {
                LabeledContent("光鸭云盘", value: "未登录")
                LabeledContent("Bangumi", value: "未登录")
            }

            Section("播放") {
                Text("M3 接入 MobileVLCKit 后开放")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
    }
}

#Preview {
    NavigationStack { SettingsView() }
}

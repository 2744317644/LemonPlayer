import SwiftUI
import LemonCore

struct SettingsView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Form {
            Section("账号") {
                switch session.state {
                case .loggedIn(let subject):
                    LabeledContent("光鸭云盘", value: subject)
                default:
                    LabeledContent("光鸭云盘", value: "未登录")
                }
                LabeledContent("Bangumi", value: "未登录")

                Button("退出登录", role: .destructive) {
                    Task { await session.logout() }
                }
            }

            Section("播放") {
                Text("M3 接入 MobileVLCKit 后开放")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("版本", value: LemonCore.version)
                LabeledContent("构建", value: LemonCore.build)
            }
        }
        .navigationTitle("设置")
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(SessionStore())
}

import SwiftUI

/// 开源许可与免责声明。
struct LicenseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("LemonPlayer 使用以下第三方组件")
                    .font(.headline)

                licenseItem(
                    name: "MobileVLCKit / libVLC",
                    license: "LGPL v2.1+",
                    note: "播放内核，提供 MKV/HEVC 解码与 libass 字幕渲染。"
                )
                licenseItem(
                    name: "FFmpeg",
                    license: "LGPL v2.1+（经 VLCKit 集成）",
                    note: "音视频解复用与解码。"
                )
                licenseItem(
                    name: "libass",
                    license: "ISC",
                    note: "ASS/SSA 字幕渲染。"
                )

                Divider()

                Text("免责声明")
                    .font(.headline)
                Text("""
                    1. 光鸭云盘未提供公开开发者 API，本项目使用社区逆向的接口，存在随时失效、限流或账号风控的风险。
                    2. 本项目仅用于播放你拥有合法访问权限的个人媒体内容，请勿用于传播侵权内容。
                    3. 播放内核以二进制依赖形式引入，按其各自许可分发。
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider()

                Link("项目主页", destination: URL(string: "https://github.com/2744317644/LemonPlayer")!)
                    .font(.footnote)
            }
            .padding()
        }
        .navigationTitle("许可与声明")
    }

    private func licenseItem(name: String, license: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(license)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack { LicenseView() }
}

import Foundation

/// 本地文件搜索。
/// 光鸭没有服务端搜索接口（见 `docs/api/GUANGYA_API.md` §3.5），
/// v1 采用「已加载列表 + 当前目录实时过滤」，全盘索引在后续版本补。
public enum FileSearch {
    public static func filter(_ files: [GuangyaFile], query: String) -> [GuangyaFile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return files }
        return files.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
}

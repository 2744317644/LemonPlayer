import Foundation

/// 文件类型。列表接口里用 `resType == 2` 判目录，`fileType` 判业务类型。
public enum FileKind: String, Sendable, Codable, CaseIterable {
    case folder
    case video
    case audio
    case image
    case document
    case archive
    case torrent
    case other

    public init(resType: Int?, fileType: Int?) {
        if resType == 2 {
            self = .folder
            return
        }
        switch fileType ?? -1 {
        case 2: self = .video
        case 3: self = .audio
        case 1: self = .image
        case 4: self = .document
        case 5: self = .archive
        case 9: self = .torrent
        default: self = .other
        }
    }
}

/// 光鸭列表项（字段名见 `docs/api/GUANGYA_API.md` §3.3）。
public struct GuangyaFile: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    public let parentID: String
    public let name: String
    public let size: Int64
    public let kind: FileKind
    public let modifiedAt: Date?
    public let ext: String?

    public var isFolder: Bool { kind == .folder }
    public var isPlayable: Bool { kind == .video || kind == .audio }

    enum CodingKeys: String, CodingKey {
        case id = "fileId"
        case parentID = "parentId"
        case name = "fileName"
        case size = "fileSize"
        case resType
        case fileType
        case ext
        case utime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // fileId 在不同实现里既有 string 也有 number，两种都接受
        if let string = try? container.decode(String.self, forKey: .id) {
            id = string
        } else if let number = try? container.decode(Int64.self, forKey: .id) {
            id = String(number)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "fileId 缺失")
        }

        parentID = (try? container.decode(String.self, forKey: .parentID)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        size = (try? container.decode(Int64.self, forKey: .size)) ?? 0
        ext = try? container.decodeIfPresent(String.self, forKey: .ext)

        let resType = try? container.decodeIfPresent(Int.self, forKey: .resType)
        let fileType = try? container.decodeIfPresent(Int.self, forKey: .fileType)
        kind = FileKind(resType: resType, fileType: fileType)

        if let unix = try? container.decodeIfPresent(Int64.self, forKey: .utime) {
            modifiedAt = Date(timeIntervalSince1970: TimeInterval(unix))
        } else {
            modifiedAt = nil
        }
    }

    public init(
        id: String,
        parentID: String,
        name: String,
        size: Int64,
        kind: FileKind,
        modifiedAt: Date? = nil,
        ext: String? = nil
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.size = size
        self.kind = kind
        self.modifiedAt = modifiedAt
        self.ext = ext
    }
}

/// 一页文件列表。
public struct FileListPage: Sendable, Equatable {
    public let total: Int
    public let items: [GuangyaFile]

    public init(total: Int, items: [GuangyaFile]) {
        self.total = total
        self.items = items
    }

    /// 分页终止：返回条数 < 请求条数，或已累计 >= total。
    public func hasMore(pageSize: Int, accumulated: Int) -> Bool {
        guard items.count >= pageSize else { return false }
        return accumulated < total
    }
}

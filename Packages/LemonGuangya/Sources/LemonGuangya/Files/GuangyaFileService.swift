import Foundation
import LemonNetwork

/// 光鸭文件接口（只读侧）。
public struct GuangyaFileService: Sendable {
    public static let apiBaseURL = URL(string: "https://api.guangyapan.com")!
    public static let webReferer = "https://www.guangyapan.com/"

    private let http: HTTPClient
    private let identity: DeviceIdentity

    public init(http: HTTPClient = HTTPClient(), identity: DeviceIdentity = .random()) {
        self.http = http
        self.identity = identity
    }

    private func headers(accessToken: String) -> [String: String] {
        [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": "application/json",
            "did": identity.deviceID,
            "dt": "4",
            "Referer": Self.webReferer,
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"
        ]
    }

    // MARK: - 目录列表

    public func listFiles(
        parentID: String,
        page: Int,
        pageSize: Int = 100,
        orderBy: Int = 3,
        sortType: Int = 1,
        fileTypes: [Int] = [],
        resType: Int? = nil,
        accessToken: String
    ) async throws -> FileListPage {
        struct Body: Encodable {
            let parentId: String
            let page: Int
            let pageSize: Int
            let orderBy: Int
            let sortType: Int
            let fileTypes: [Int]
            let resType: Int?
        }

        let request = try HTTPRequest.json(
            url: Self.apiBaseURL.appendingPathComponent("userres/v1/file/get_file_list"),
            headers: headers(accessToken: accessToken),
            body: Body(
                parentId: parentID,
                page: page,
                pageSize: pageSize,
                orderBy: orderBy,
                sortType: sortType,
                fileTypes: fileTypes,
                resType: resType
            )
        )
        let response = try await http.send(request)
        let envelope = try decodeEnvelope(response)
        return FileListPage(total: envelope.total, items: envelope.items)
    }

    /// 全盘媒体扫描结果：目录（用于还原番剧目录层级）+ 文件。
    public struct MediaScanResult: Sendable {
        public let folders: [GuangyaFile]
        public let files: [GuangyaFile]

        public init(folders: [GuangyaFile], files: [GuangyaFile]) {
            self.folders = folders
            self.files = files
        }

        public var videos: [GuangyaFile] {
            files.filter { $0.kind == .video }
        }
    }

    /// 递归扫描全盘：返回目录树节点 + 文件（媒体库刮削用）。
    public func listAllMedia(
        pageSize: Int = 100,
        maxPages: Int = 30,
        maxFolders: Int = 600,
        maxFiles: Int = 20000,
        accessToken: String
    ) async throws -> MediaScanResult {
        var folders: [GuangyaFile] = []
        var files: [GuangyaFile] = []
        var queue: [String] = [""]
        var visited = Set<String>()

        while !queue.isEmpty {
            if Task.isCancelled || folders.count >= maxFolders || files.count >= maxFiles { break }
            let parent = queue.removeFirst()
            guard visited.insert(parent).inserted else { continue }

            var page = 0
            while page < maxPages {
                let current: FileListPage
                do {
                    current = try await listFiles(
                        parentID: parent,
                        page: page,
                        pageSize: pageSize,
                        orderBy: 3,
                        sortType: 0,
                        accessToken: accessToken
                    )
                } catch {
                    break
                }

                for item in current.items {
                    if item.isFolder {
                        if folders.count < maxFolders {
                            folders.append(item)
                            queue.append(item.id)
                        }
                    } else if files.count < maxFiles {
                        files.append(item)
                    }
                }

                if current.items.count < pageSize || files.count >= maxFiles { break }
                page += 1
            }
        }
        return MediaScanResult(folders: folders, files: files)
    }

    /// 全盘视频聚合：优先 `parentId:"*" + resType:1 + fileTypes:[2]`；
    /// 若服务端返回的仍是目录（旧行为），回退为递归遍历。
    public func listAllVideos(
        pageSize: Int = 100,
        maxPages: Int = 20,
        accessToken: String
    ) async throws -> [GuangyaFile] {
        var aggregated: [GuangyaFile] = []
        var page = 0
        while page < maxPages {
            let current = try await listFiles(
                parentID: "*",
                page: page,
                pageSize: pageSize,
                orderBy: 3,
                sortType: 1,
                fileTypes: [2],
                resType: 1,
                accessToken: accessToken
            )
            let videos = current.items.filter { !$0.isFolder && $0.kind == .video }
            aggregated.append(contentsOf: videos)
            if current.items.count < pageSize || aggregated.count >= 5000 {
                break
            }
            page += 1
        }
        if !aggregated.isEmpty {
            return aggregated
        }
        let media = try await listAllMedia(pageSize: pageSize, maxPages: maxPages, accessToken: accessToken)
        return media.videos
    }

    // MARK: - 播放直链

    /// `POST /nd.bizuserres.s/v1/file/get_res_download_url`
    /// 取值顺序：`data.signedURL` 优先，其次 `data.downloadUrl`（三份实现一致）。
    public func playbackURL(fileID: String, accessToken: String) async throws -> PlaybackLink {
        struct Body: Encodable {
            let fileId: String
        }

        let request = try HTTPRequest.json(
            url: Self.apiBaseURL.appendingPathComponent("userres/v1/get_res_download_url"),
            headers: headers(accessToken: accessToken),
            body: Body(fileId: fileID)
        )
        let response = try await http.send(request)

        guard response.isSuccess else {
            throw response.statusCode == 401 ? GuangyaError.tokenExpired : GuangyaError.requestFailed(statusCode: response.statusCode, message: "HTTP \(response.statusCode)")
        }
        return try PlaybackLink.decode(from: response.data)
    }

    // MARK: - 响应解析

    private struct Envelope: Decodable {
        struct Payload: Decodable {
            let total: Int?
            let list: [GuangyaFile]?
        }

        // 成功响应通常没有 code 字段（只有 msg/data），错误响应才有 code
        let code: Int?
        let msg: String?
        let data: Payload?
    }

    private func decodeEnvelope(_ response: HTTPResponse) throws -> (total: Int, items: [GuangyaFile]) {
        guard response.isSuccess else {
            if response.statusCode == 401 {
                throw GuangyaError.tokenExpired
            }
            let snippet = Self.snippet(response.data)
            throw GuangyaError.requestFailed(
                statusCode: response.statusCode,
                message: "HTTP \(response.statusCode) \(snippet)"
            )
        }
        return try Self.parseFileListResponse(response.data)
    }

    /// 纯解析（可单测）：成功响应 `{msg,data:{total,list}}` 没有 `code`；
    /// 错误响应才有 `code`（117 = token 失效）。
    static func parseFileListResponse(_ data: Data) throws -> (total: Int, items: [GuangyaFile]) {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw GuangyaError.api(
                code: -1,
                message: "响应解析失败：\(Self.snippet(data))"
            )
        }

        let code = envelope.code ?? 0
        guard code == 0 else {
            if code == 117 {
                throw GuangyaError.tokenExpired
            }
            throw GuangyaError.api(code: code, message: envelope.msg ?? "未知错误")
        }

        let payload = envelope.data
        return (payload?.total ?? 0, payload?.list ?? [])
    }

    /// 响应体前 200 字符（诊断用，不含 token；token 在 header 里）。
    private static func snippet(_ data: Data) -> String {
        guard let text = String(data: data.prefix(200), encoding: .utf8) else { return "<binary>" }
        return text.replacingOccurrences(of: "\n", with: " ")
    }
}

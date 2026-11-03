import Foundation
import LemonNetwork

/// 光鸭文件接口（只读侧）。
public struct GuangyaFileService: Sendable {
    public static let apiBaseURL = URL(string: "https://api.guangyapan.com")!
    public static let webReferer = "https://www.guangyupan.com/"

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
        accessToken: String
    ) async throws -> FileListPage {
        struct Body: Encodable {
            let parentId: String
            let page: Int
            let pageSize: Int
            let orderBy: Int
            let sortType: Int
        }

        let request = try HTTPRequest.json(
            url: Self.apiBaseURL.appendingPathComponent("nd.bizuserres.s/v1/file/get_file_list"),
            headers: headers(accessToken: accessToken),
            body: Body(parentId: parentID, page: page, pageSize: pageSize, orderBy: orderBy, sortType: sortType)
        )
        let response = try await http.send(request)
        let envelope = try decodeEnvelope(response)
        return FileListPage(total: envelope.total, items: envelope.items)
    }

    // MARK: - 播放直链

    /// `POST /nd.bizuserres.s/v1/file/get_res_download_url`
    /// 取值顺序：`data.signedURL` 优先，其次 `data.downloadUrl`（三份实现一致）。
    public func playbackURL(fileID: String, accessToken: String) async throws -> PlaybackLink {
        struct Body: Encodable {
            let fileId: String
        }

        let request = try HTTPRequest.json(
            url: Self.apiBaseURL.appendingPathComponent("nd.bizuserres.s/v1/file/get_res_download_url"),
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

        let code: Int
        let msg: String?
        let data: Payload?
    }

    private func decodeEnvelope(_ response: HTTPResponse) throws -> (total: Int, items: [GuangyaFile]) {
        guard response.isSuccess else {
            if response.statusCode == 401 {
                throw GuangyaError.tokenExpired
            }
            throw GuangyaError.requestFailed(
                statusCode: response.statusCode,
                message: "HTTP \(response.statusCode)"
            )
        }

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: response.data)
        } catch {
            throw GuangyaError.api(code: -1, message: "响应解析失败")
        }

        guard envelope.code == 0 else {
            if envelope.code == 117 {
                throw GuangyaError.tokenExpired
            }
            throw GuangyaError.api(code: envelope.code, message: envelope.msg ?? "未知错误")
        }

        let payload = envelope.data
        return (payload?.total ?? 0, payload?.list ?? [])
    }
}

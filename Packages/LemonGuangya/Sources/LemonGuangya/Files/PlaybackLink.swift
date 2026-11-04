import Foundation

/// 播放直链（由 `get_res_download_url` 返回）。
/// 有效期、CDN 形态、防盗链策略在 `docs/api/GUANGYA_API.md` 中标为"待验证"，
/// 因此这里不假设固定 TTL，播放器按"短寿命 + 403 自动重取"处理（ADR-013）。
public struct PlaybackLink: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]

    public init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }

    /// 直链请求必须携带的头部：Referer 与浏览器 UA（两个参考实现都这么做）。
    public static func playbackHeaders() -> [String: String] {
        [
            "Referer": "https://www.guangyapan.com/",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"
        ]
    }

    /// 解析 `get_res_download_url` 的响应体（成功为 `{msg,data:{signedURL,downloadUrl}}`，无 code）。
    public static func decode(from data: Data) throws -> PlaybackLink {
        struct Envelope: Decodable {
            struct Payload: Decodable {
                let signedURL: String?
                let downloadUrl: String?
            }
            let code: Int?
            let msg: String?
            let data: Payload?
        }

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw GuangyaError.api(code: -1, message: "直链响应解析失败")
        }
        let code = envelope.code ?? 0
        guard code == 0 else {
            throw code == 117 ? GuangyaError.tokenExpired : GuangyaError.api(code: code, message: envelope.msg ?? "未知错误")
        }
        // signedURL 为空串时也要回退 downloadUrl（实现用 `or`，不是 `??`）
        let rawURL: String? = {
            if let signed = envelope.data?.signedURL, !signed.isEmpty { return signed }
            if let download = envelope.data?.downloadUrl, !download.isEmpty { return download }
            return nil
        }()
        guard let rawURL, let url = URL(string: rawURL) else {
            throw GuangyaError.api(code: -2, message: "直链为空")
        }
        return PlaybackLink(url: url, headers: playbackHeaders())
    }
}

import Foundation

#if canImport(CoreFoundation) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
import CoreFoundation
#endif

/// 字幕文本解码：BOM 优先，其次 UTF-8，再退化到 GB18030 / BIG5 / Latin-1。
/// 中文 SRT 大量是 GBK/GB18030，自动识别是可用性关键。
///
/// 注意：GB18030 / BIG5 依赖 Apple 平台的 CoreFoundation 编码转换；
/// Linux（swift-corelibs-foundation）不支持，因此该分支按平台条件编译，
/// 纯逻辑包可以在 Linux 上跑单测（CI 与本地 WSL 双端验证）。
public enum SubtitleTextDecoder {
    public struct DecodedText: Equatable, Sendable {
        public let text: String
        public let encoding: String.Encoding

        public init(text: String, encoding: String.Encoding) {
            self.text = text
            self.encoding = encoding
        }
    }

    public static var supportsChineseLegacyEncodings: Bool {
        #if canImport(CoreFoundation) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        return true
        #else
        return false
        #endif
    }

    #if canImport(CoreFoundation) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
    public static var gb18030: String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    }

    public static var big5: String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
    }
    #endif

    public static func decode(_ data: Data) -> (text: String, encoding: String.Encoding) {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            if let text = String(data: data.dropFirst(3), encoding: .utf8) {
                return (text, .utf8)
            }
        }
        if data.starts(with: [0xFF, 0xFE]) {
            if let text = String(data: data, encoding: .utf16LittleEndian) {
                return (text, .utf16LittleEndian)
            }
        }
        if data.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16BigEndian) {
                return (text, .utf16BigEndian)
            }
        }
        if let text = String(data: data, encoding: .utf8) {
            return (text, .utf8)
        }

        #if canImport(CoreFoundation) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        if let text = String(data: data, encoding: gb18030) {
            return (text, gb18030)
        }
        if let text = String(data: data, encoding: big5) {
            return (text, big5)
        }
        #endif

        return (String(data: data, encoding: .isoLatin1) ?? "", .isoLatin1)
    }
}

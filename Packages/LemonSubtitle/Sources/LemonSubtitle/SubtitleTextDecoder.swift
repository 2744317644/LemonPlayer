import Foundation
import CoreFoundation

/// 字幕文本解码：BOM 优先，其次 UTF-8，再退化到 GB18030 / BIG5 / Latin-1。
/// 中文 SRT 大量是 GBK/GB18030，自动识别是可用性关键。
public enum SubtitleTextDecoder {
    public static var gb18030: String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    }

    public static var big5: String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
    }

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
        if let text = String(data: data, encoding: gb18030) {
            return (text, gb18030)
        }
        if let text = String(data: data, encoding: big5) {
            return (text, big5)
        }
        return (String(data: data, encoding: .isoLatin1) ?? "", .isoLatin1)
    }
}

import Foundation

/// 光鸭云盘要求的设备标识。
/// 服务端要求：`did` / `x-device-id` 为 32 位小写 hex；`x-device-sign` 形如 `wdi10.<did><32 hex>`。
/// 该值与 token 绑定，同一安装内必须保持不变，因此需要持久化。
public struct DeviceIdentity: Codable, Sendable, Equatable {
    public let deviceID: String
    public let sign: String

    public init(deviceID: String, sign: String) {
        self.deviceID = deviceID
        self.sign = sign
    }

    public static func random() -> DeviceIdentity {
        let deviceID = Self.randomHex()
        return DeviceIdentity(deviceID: deviceID, sign: "wdi10.\(deviceID)\(Self.randomHex())")
    }

    private static func randomHex() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<16)
            .map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }
            .joined()
    }
}

import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// 启动耗时与内存占用（诊断页展示，Step 9）。
@MainActor
public enum AppMetrics {
    /// App 进程启动时间（首次访问静态属性时建立，尽量贴近启动点）。
    public static let launchStartedAt = Date()
    private(set) public static var launchDuration: TimeInterval?

    /// 根界面出现后调用一次。
    public static func markReady() {
        guard launchDuration == nil else { return }
        launchDuration = Date().timeIntervalSince(launchStartedAt)
    }

    /// 当前 App 常驻内存（字节）；非 Darwin 平台返回 0。
    public static var memoryBytes: UInt64 {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
        #else
        return 0
        #endif
    }

    public static var memoryText: String {
        let bytes = memoryBytes
        guard bytes > 0 else { return "不可用" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    public static var launchText: String {
        guard let launchDuration else { return "测量中" }
        return String(format: "%.2fs", launchDuration)
    }
}

import Foundation
import Observation
import UIKit
import LemonCore
import LemonGuangya
import LemonNetwork

/// 扫码登录状态机：申请设备码 → 展示二维码 → 轮询 → 授权成功/过期/失败。
///
/// 真机上的两个关键问题（2026-11 联调）：
/// 1. 切到光鸭 App 扫码时本 App 被挂起，回来后首个请求可能因"无网络"失败 → 不能中止轮询，要重试；
/// 2. 设备码只有 120 秒有效期 → 过期后自动换新码，避免"刷新→再扫"的循环。
@MainActor
@Observable
final class LoginViewModel {
    enum Phase: Equatable {
        case loading
        case waiting(DeviceCode)
        case expired
        case failed(String)
        case success
    }

    private(set) var phase: Phase = .loading
    private(set) var qrImage: UIImage?

    private let auth: GuangyaAuthClient
    private let onAuthorized: @MainActor (TokenBundle) async -> Void
    private var autoRefreshCount = 0

    init(auth: GuangyaAuthClient, onAuthorized: @escaping @MainActor (TokenBundle) async -> Void) {
        self.auth = auth
        self.onAuthorized = onAuthorized
    }

    func start() async {
        phase = .loading
        qrImage = nil
        do {
            let code = try await auth.requestDeviceCode()
            qrImage = QRCodeImage.make(from: code.qrContent)
            phase = .waiting(code)
            Task { await DiagnosticsCenter.shared.log(.info, "auth", "设备码已获取，有效期 \(code.expiresIn)s，轮询间隔 \(code.interval)s") }
            await poll(code)
        } catch is CancellationError {
            return
        } catch {
            let message = Self.describe(error)
            Task { await DiagnosticsCenter.shared.log(.error, "auth", "获取设备码失败：\(message)") }
            phase = .failed(message)
        }
    }

    /// App 回到前台时调用：失败/过期状态下自动重试，而不是让用户手动刷新。
    func retryIfNeeded() async {
        switch phase {
        case .failed, .expired:
            await start()
        case .waiting:
            break
        case .loading, .success:
            break
        }
    }

    private func poll(_ code: DeviceCode) async {
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        let baseInterval = max(Double(code.interval), 2)
        var interval = baseInterval
        var consecutiveFailures = 0

        while Date() < deadline {
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return // 视图消失
            }
            if Task.isCancelled { return }

            do {
                switch try await auth.poll(deviceCode: code.deviceCode) {
                case .pending:
                    consecutiveFailures = 0
                    interval = baseInterval
                case .authorized(let bundle):
                    Task { await DiagnosticsCenter.shared.log(.info, "auth", "扫码授权成功") }
                    phase = .success
                    await onAuthorized(bundle)
                    return
                case .expired:
                    Task { await DiagnosticsCenter.shared.log(.warning, "auth", "设备码已过期，自动换新码") }
                    await refreshCode()
                    return
                case .failed(let message):
                    consecutiveFailures += 1
                    Task { await DiagnosticsCenter.shared.log(.warning, "auth", "轮询失败(\(consecutiveFailures))：\(message)") }
                    if consecutiveFailures >= 3 {
                        phase = .failed(message)
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                // 网络抖动/从后台回来：不退出流程，退避后继续轮询
                consecutiveFailures += 1
                let message = Self.describe(error)
                Task { await DiagnosticsCenter.shared.log(.warning, "auth", "轮询网络异常(\(consecutiveFailures))：\(message)") }
                if consecutiveFailures >= 6 {
                    phase = .failed("网络异常，请检查网络后重试")
                    return
                }
                interval = min(interval * 2, 6)
            }
        }

        await refreshCode()
    }

    private func refreshCode() async {
        guard autoRefreshCount < 3 else {
            phase = .expired
            return
        }
        autoRefreshCount += 1
        await start()
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? GuangyaError { return error.localizedDescription }
        if let error = error as? HTTPError { return error.localizedDescription }
        return error.localizedDescription
    }
}

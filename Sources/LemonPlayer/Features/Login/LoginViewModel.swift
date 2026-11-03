import Foundation
import Observation
import UIKit
import LemonGuangya
import LemonNetwork

/// 扫码登录状态机：申请设备码 → 展示二维码 → 轮询 → 授权成功/过期/失败。
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
            await poll(code)
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    private func poll(_ code: DeviceCode) async {
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        let interval = max(code.interval, 1)

        while Date() < deadline {
            do {
                try await Task.sleep(for: .seconds(Double(interval)))
            } catch {
                return // 视图消失导致的取消
            }
            if Task.isCancelled { return }

            do {
                switch try await auth.poll(deviceCode: code.deviceCode) {
                case .pending:
                    continue
                case .authorized(let bundle):
                    phase = .success
                    await onAuthorized(bundle)
                    return
                case .expired:
                    phase = .expired
                    return
                case .failed(let message):
                    phase = .failed(message)
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(Self.describe(error))
                return
            }
        }
        phase = .expired
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? GuangyaError {
            return error.localizedDescription
        }
        if let error = error as? HTTPError {
            return error.localizedDescription
        }
        return error.localizedDescription
    }
}

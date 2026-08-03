import Foundation

/// A narrow Companion Client boundary over the existing OpenClaw Gateway runtime.
///
/// This protocol deliberately models SoulNest use cases rather than exposing a
/// WebSocket, provider, or transport abstraction to SwiftUI. The production
/// adapter must delegate to OpenClaw's existing pairing, authentication, event,
/// reconnect, and chat implementation.
@MainActor
protocol SoulNestGatewayClient: AnyObject {
    var state: SoulNestGatewayConnectionState { get }
    var events: AsyncStream<SoulNestGatewayEvent> { get }

    func connect(to endpoint: SoulNestGatewayEndpoint) async throws
    func disconnect() async
    func cancelPairing() async
    func sendText(_ text: String, sessionKey: String) async throws -> String
}

struct SoulNestGatewayEndpoint: Equatable, Sendable {
    let url: URL
    let stableID: String?

    init(url: URL, stableID: String? = nil) throws {
        guard let scheme = url.scheme?.lowercased(), ["ws", "wss", "http", "https"].contains(scheme),
              url.host != nil
        else {
            throw SoulNestGatewayError.invalidEndpoint
        }
        self.url = url
        self.stableID = stableID
    }
}

enum SoulNestGatewayConnectionState: Equatable, Sendable {
    case disconnected
    case pairing
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(SoulNestGatewayError)
}

enum SoulNestGatewayEvent: Equatable, Sendable {
    case connectionChanged(SoulNestGatewayConnectionState)
    case assistantText(requestID: String, text: String, isFinal: Bool)
    case requestFailed(requestID: String?, error: SoulNestGatewayError)
}

enum SoulNestGatewayError: Error, Equatable, Sendable {
    case invalidEndpoint
    case pairingFailed
    case authenticationFailed
    case networkUnavailable
    case gatewayUnavailable
    case requestTimedOut
    case cancelled
    case sessionExpired
    case malformedResponse
    case notConnected
    case unknown(String)

    var userMessage: String {
        switch self {
        case .invalidEndpoint:
            "Gateway 位址無效。"
        case .pairingFailed:
            "無法完成 Gateway 配對，請重新確認配對資訊。"
        case .authenticationFailed:
            "Gateway 驗證失敗，請重新配對。"
        case .networkUnavailable:
            "目前網路無法連線。"
        case .gatewayUnavailable:
            "Gateway 暫時無法使用。"
        case .requestTimedOut:
            "Gateway 回應逾時，請重試。"
        case .cancelled:
            "操作已取消。"
        case .sessionExpired:
            "這個對話 Session 已失效，需要重新建立。"
        case .malformedResponse:
            "Gateway 回傳了無法辨識的資料。"
        case .notConnected:
            "尚未連線到 Gateway。"
        case let .unknown(message):
            message.isEmpty ? "發生未知的 Gateway 錯誤。" : message
        }
    }
}

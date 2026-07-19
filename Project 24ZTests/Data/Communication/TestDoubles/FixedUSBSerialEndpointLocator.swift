import Foundation
@testable import Project_24Z

/// Adapter identity Probe testへ固定Endpoint配列を返します。
struct FixedUSBSerialEndpointLocator: USBSerialEndpointLocating {
    /// 返す固定Endpoint配列です。
    let endpoints: [TransportEndpoint]

    /// 固定Endpoint配列を返します。
    /// - Returns: 初期化時に注入した配列。
    func locateApprovedEndpoints() throws -> [TransportEndpoint] {
        endpoints
    }
}

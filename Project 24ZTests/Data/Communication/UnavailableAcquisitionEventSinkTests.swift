import Foundation
import Testing
@testable import Project_24Z

/// Production保存pipeline未接続時のRuntime Event停止境界を検証します。
struct UnavailableAcquisitionEventSinkTests {
    /// 受信bytesをqueue受理または保存成功として返さないことを検証します。
    @Test
    func eventAcceptanceNeverReportsSuccess() async {
        let sink = UnavailableAcquisitionEventSink()

        await #expect(throws: CommunicationRuntimeError.storageUnavailable) {
            try await sink.accept(
                .transportBytes(Data([0x01]), generation: .init(value: 1))
            )
        }
    }
}

#if os(macOS)
import Darwin
import Dispatch
import Foundation

/// OBDLink EXの115200/8N1・flow controlなしのmacOS USB serial Transportです。
actor MacOSUSBSerialTransport: CommunicationTransport {
    private var descriptor: Int32 = -1
    private var generation: ConnectionGeneration?
    private var readSource: DispatchSourceRead?

    /// callout endpointを一つだけ開き、受信callbackを開始します。
    /// - Parameters:
    ///   - endpoint: IOKit Descriptor照合済みUSB serial endpoint。
    ///   - generation: 今回のprocess-local接続世代。
    ///   - eventHandler: 受信、切断、失敗を通知するcallback。
    /// - Throws: endpoint種別、open、termios設定が不正な場合。
    func open(
        endpoint: TransportEndpoint,
        generation: ConnectionGeneration,
        eventHandler: @escaping @Sendable (TransportEvent) -> Void
    ) async throws {
        guard endpoint.kind == .usbSerial, descriptor == -1 else {
            throw CommunicationRuntimeError.transportUnavailable
        }

        let opened = Darwin.open(endpoint.identifier, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard opened >= 0 else { throw CommunicationRuntimeError.transportUnavailable }
        do {
            try Self.configure(descriptor: opened)
        } catch {
            Darwin.close(opened)
            throw error
        }

        descriptor = opened
        self.generation = generation
        let source = DispatchSource.makeReadSource(
            fileDescriptor: opened,
            queue: DispatchQueue(label: "project24z.usb-serial.read")
        )
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(opened, &buffer, buffer.count)
            if count > 0 {
                eventHandler(.received(Data(buffer.prefix(count))))
            } else if count == 0 {
                eventHandler(.disconnected)
            } else if errno != EAGAIN && errno != EWOULDBLOCK {
                eventHandler(.failed)
            }
        }
        source.setCancelHandler {
            Darwin.close(opened)
        }
        readSource = source
        source.resume()
        eventHandler(.connected)
    }

    /// 現在Generationへbytesを全量書き込みます。
    /// - Parameters:
    ///   - bytes: allowlistが生成した固定bytes。
    ///   - generation: open時と一致すべき接続世代。
    /// - Throws: stale generation、切断、partial write停止。
    func write(_ bytes: Data, generation: ConnectionGeneration) async throws {
        guard descriptor >= 0, self.generation == generation else {
            throw CommunicationRuntimeError.staleGeneration
        }
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                return Darwin.write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
            }
            if written > 0 {
                offset += written
            } else if written < 0, errno == EINTR {
                continue
            } else {
                throw CommunicationRuntimeError.transportUnavailable
            }
        }
    }

    /// callbackを停止し、cancel handlerでdescriptorを一度だけ閉じます。
    func close() async {
        generation = nil
        descriptor = -1
        let source = readSource
        readSource = nil
        source?.cancel()
    }

    /// Runbookで実測済みの115200 bps、8N1、flow controlなしへ設定します。
    /// - Parameter descriptor: open済みserial file descriptor。
    /// - Throws: termios取得または適用失敗。
    private static func configure(descriptor: Int32) throws {
        var options = termios()
        guard tcgetattr(descriptor, &options) == 0 else {
            throw CommunicationRuntimeError.transportUnavailable
        }
        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD | CS8)
        options.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)
        guard cfsetspeed(&options, speed_t(B115200)) == 0,
              tcsetattr(descriptor, TCSANOW, &options) == 0 else {
            throw CommunicationRuntimeError.transportUnavailable
        }
        _ = tcflush(descriptor, TCIOFLUSH)
    }
}
#endif

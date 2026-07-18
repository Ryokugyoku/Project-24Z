import Foundation
import Testing
@testable import Project_24Z

/// ELM framingとunknown／malformed Raw保持を検証します。
struct ELMResponseFramerTests {
    /// 分割promptと複数行を一つのRaw応答として保持します。
    @Test
    func splitPromptFramesMultilineRawResponse() {
        var framer = ELMResponseFramer()
        #expect(framer.append(Data("41 0C\r41 0D\r".utf8)) == nil)
        let framed = framer.append(Data(">tail".utf8))
        #expect(framed?.raw == Data("41 0C\r41 0D\r>".utf8))
        #expect(framed?.promptRange == 12..<13)
    }

    /// 非UTF-8をmalformedとしてRawのまま保持できます。
    @Test
    func nonUTF8IsMalformedWithoutDroppingRaw() {
        let raw = Data([0xFF, 0x3E])
        #expect(ELMResponseClassifier().classify(raw) == .malformed)
        #expect(raw == Data([0xFF, 0x3E]))
    }

    /// 未知statusをdata成功へ昇格しません。
    @Test
    func unknownStatusRemainsUnknown() {
        #expect(ELMResponseClassifier().classify(Data("VENDOR MYSTERY\r>".utf8)) == .unknownStatus)
    }
}

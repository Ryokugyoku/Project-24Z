/// ECUごとのPID系列をVersion付きで一意に表す純粋Domain値です。
nonisolated struct PIDSignalIdentity: Equatable, Hashable, Sendable {
    /// 異なる信号体系を混同しない名前空間です。
    enum Namespace: Equatable, Hashable, Sendable {
        /// 承認済み標準OBD PIDです。
        case standardOBD
        /// メーカー固有PIDです。標準PIDへ推測統合しません。
        case manufacturerSpecific
        /// Raw CAN信号です。診断PIDとは別系列です。
        case rawCAN
    }

    /// 信号体系です。
    let namespace: Namespace
    /// Version付きCatalogが指定したServiceまたはMode codeです。
    let serviceOrMode: UInt8
    /// Version付きCatalogが指定したPID codeです。
    let parameter: UInt8
    /// 応答元ECUの不透明なbytesです。
    let ecuSource: [UInt8]
    /// 診断protocolの安定codeです。
    let diagnosticProtocolKind: String
    /// Rawを解釈したDecoder bundle Versionです。
    let decoderBundleVersion: String
}

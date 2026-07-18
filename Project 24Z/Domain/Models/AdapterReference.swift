/// ユーザースコープ内で物理Adapter候補を監査する不透明参照です。
nonisolated struct AdapterReference: Equatable, Hashable, Sendable {
    let opaqueID: String
}

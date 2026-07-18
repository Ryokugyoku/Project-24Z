import Foundation

/// 一テスト専用のDBディレクトリを安全に所有します。
struct TemporaryVehicleDatabase {
    /// DBファイルURLです。
    let url: URL
    private let directory: URL

    /// UUID名の一時ディレクトリを作成します。
    /// - Throws: ディレクトリ作成エラー。
    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("project24z-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("vehicle-identity.sqlite")
    }

    /// このfixtureが作成した一時ディレクトリだけを削除します。
    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

import CryptoKit
import Foundation
import GRDB

/// Origin Change Chain v1の決定的SQLite scalar functionを提供します。
enum SyncChainDigestV1 {
    /// schema Triggerが利用する関数名です。
    nonisolated static let functionName = "sync_chain_digest_v1"

    /// GRDB接続へVersion固定のchain digest関数を登録します。
    /// - Parameter database: 新しく準備されたGRDB接続。
    /// - Note: 値は型tag、NULL tag、8 byte長、payloadの順で束縛し、曖昧な連結を避けます。
    nonisolated static func register(in database: Database) {
        database.add(function: DatabaseFunction(functionName, argumentCount: 18, pure: true) { values in
            Data(SHA256.hash(data: canonicalData(values)))
        })
    }

    /// SQLite値列を型と長さ付きのcanonical bytesへ変換します。
    /// - Parameter values: SQL functionへ渡された順序固定値。
    /// - Returns: Chain v1用の曖昧性のないbytes。
    nonisolated private static func canonicalData(_ values: [DatabaseValue]) -> Data {
        var output = Data("project24z.sync-chain.v1".utf8)
        for value in values {
            switch value.storage {
            case .null:
                append(tag: 0, payload: Data(), to: &output)
            case .int64(let integer):
                var bigEndian = UInt64(bitPattern: integer).bigEndian
                append(tag: 1, payload: Data(bytes: &bigEndian, count: 8), to: &output)
            case .double(let number):
                var bits = number.bitPattern.bigEndian
                append(tag: 2, payload: Data(bytes: &bits, count: 8), to: &output)
            case .string(let string):
                append(tag: 3, payload: Data(string.utf8), to: &output)
            case .blob(let data):
                append(tag: 4, payload: data, to: &output)
            }
        }
        return output
    }

    /// 一つの型付き値を出力へ追加します。
    /// - Parameters:
    ///   - tag: SQLite storage classを区別するtag。
    ///   - payload: 値のcanonical bytes。
    ///   - output: 追記先。
    nonisolated private static func append(tag: UInt8, payload: Data, to output: inout Data) {
        output.append(tag)
        var length = UInt64(payload.count).bigEndian
        output.append(Data(bytes: &length, count: 8))
        output.append(payload)
    }
}

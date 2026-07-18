import Foundation

/// DB契約のUTC・マイクロ秒付きRFC 3339日時を変換します。
nonisolated enum GRDBVehicleDateCodec {
    /// Dateを固定長UTC文字列へ変換します。
    /// - Parameter date: 変換する日時。
    /// - Returns: UTC・マイクロ秒付きRFC 3339文字列。
    static func string(from date: Date) -> String {
        makeFormatter().string(from: date)
    }

    /// DB文字列をDateへ戻します。
    /// - Parameter value: DBから取得した固定長日時。
    /// - Returns: 構文が正しければDate、そうでなければnil。
    static func date(from value: String) -> Date? {
        makeFormatter().date(from: value)
    }

    /// 呼出しごとに独立したPOSIX固定Localeの日時Formatterを作ります。
    /// - Returns: DB契約専用のFormatter。
    private static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        return formatter
    }
}

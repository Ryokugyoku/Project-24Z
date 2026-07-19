#if os(iOS)
import SwiftUI

/// iOS専用の設定画面階層です。
struct IOSSettingsView: View {
    /// 標準Navigationで設定項目を表示します。
    var body: some View {
        NavigationStack {
            List {
                Section("接続") {
                    NavigationLink("接続設定") { IOSConnectionSettingsView() }
                }
#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
                Section("Development") {
                    NavigationLink("データベース閲覧") { IOSDevelopmentDatabaseBrowserView() }
                }
#endif
            }
            .navigationTitle("設定")
        }
        .accessibilityIdentifier("project24z.settings")
    }
}
#endif

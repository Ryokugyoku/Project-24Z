#if os(macOS)
import SwiftUI

/// macOS専用の設定画面階層です。
struct MacOSSettingsView: View {
    /// 標準Navigationで設定項目を表示します。
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("接続設定") { MacOSConnectionSettingsView() }
#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
                Section("Development") {
                    NavigationLink("データベース閲覧") { MacOSDevelopmentDatabaseBrowserView() }
                }
#endif
            }
            .navigationTitle("設定")
        }
        .accessibilityIdentifier("project24z.settings")
    }
}
#endif

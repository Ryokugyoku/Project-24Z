#if os(iOS)
import SwiftUI

/// iOS専用の画面階層を開始します。
struct IOSRootView: View {
    @StateObject private var model: ItemListModel

    /// iOSのルート画面を生成します。
    /// - Parameter itemRepository: 項目一覧が使用するリポジトリ。
    init(itemRepository: any ItemRepository) {
        _model = StateObject(wrappedValue: ItemListModel(repository: itemRepository))
    }

    var body: some View {
        IOSItemListView(model: model)
    }
}
#endif

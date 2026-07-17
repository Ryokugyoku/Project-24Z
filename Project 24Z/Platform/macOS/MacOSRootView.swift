#if os(macOS)
import SwiftUI

/// macOS専用の画面階層を開始します。
struct MacOSRootView: View {
    @StateObject private var model: ItemListModel

    /// macOSのルート画面を生成します。
    /// - Parameter itemRepository: 項目一覧が使用するリポジトリ。
    init(itemRepository: any ItemRepository) {
        _model = StateObject(wrappedValue: ItemListModel(repository: itemRepository))
    }

    var body: some View {
        MacOSItemListView(model: model)
    }
}
#endif

#if os(iOS)
import SwiftUI

/// iOSの操作体系とレイアウトで項目一覧を表示します。
struct IOSItemListView: View {
    @ObservedObject var model: ItemListModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.items) { item in
                    Text(item.timestamp, format: .dateTime)
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle("Items")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus", action: model.addItem)
                }
            }
            .overlay {
                if model.items.isEmpty {
                    ContentUnavailableView("No Items", systemImage: "tray")
                }
            }
            .task {
                model.load()
            }
            .alert("Unable to Update Items", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "Unknown error")
            }
        }
    }

    /// iOSのスワイプ削除位置をDomainエンティティへ変換します。
    /// - Parameter offsets: 一覧上で削除された位置。
    private func deleteItems(at offsets: IndexSet) {
        for offset in offsets where model.items.indices.contains(offset) {
            model.delete(model.items[offset])
        }
    }

    /// エラーメッセージの有無をAlert表示状態へ変換します。
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { _ in }
        )
    }
}
#endif

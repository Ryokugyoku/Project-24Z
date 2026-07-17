#if os(macOS)
import SwiftUI

/// macOSのウインドウ操作とサイドバー構成で項目一覧を表示します。
struct MacOSItemListView: View {
    @ObservedObject var model: ItemListModel
    @State private var selection: Item.ID?

    var body: some View {
        NavigationSplitView {
            List(model.items, selection: $selection) { item in
                Text(item.timestamp, format: .dateTime)
                    .tag(item.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            model.delete(item)
                        }
                    }
            }
            .navigationTitle("Items")
            .toolbar {
                Button("Add", systemImage: "plus", action: model.addItem)
            }
            .frame(minWidth: 220)
        } detail: {
            if let selectedItem {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Item")
                        .font(.title)
                    Text(selectedItem.timestamp, format: .dateTime)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
            } else {
                ContentUnavailableView("Select an Item", systemImage: "sidebar.left")
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

    /// 現在の選択IDに対応する項目を返します。
    private var selectedItem: Item? {
        model.items.first { $0.id == selection }
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

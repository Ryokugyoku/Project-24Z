#if os(iOS)
#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
import SwiftUI

/// iOS専用の開発用read-only Database Browserです。
struct IOSDevelopmentDatabaseBrowserView: View {
    /// Composition Rootから注入されたread-only Modelです。
    @EnvironmentObject private var model: DevelopmentDatabaseBrowserModel

    /// 注意、selector、縦横table、detailをiOS専用構成で表示します。
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("開発専用。実データを表示します。編集・削除はできません。", systemImage: "lock.shield")
                .font(.footnote)
            Picker("データソース", selection: sourceSelection) {
                Text("未選択").tag(DevelopmentDatabaseSource?.none)
                ForEach(model.state.sources, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }
            Picker("table / dataset", selection: targetSelection) {
                Text("未選択").tag(DevelopmentDatabaseTarget?.none)
                ForEach(model.state.targets, id: \.self) { Text($0.name).tag(Optional($0)) }
            }
            summary
            tableArea
        }
        .padding()
        .navigationTitle("データベース閲覧")
        .privacySensitive()
        .task { await model.perform(.loadSources) }
        .sheet(isPresented: detailPresented) { detailSheet }
    }

    /// 選択対象の件数・列数・更新操作です。
    private var summary: some View {
        HStack {
            Text("列 \(model.state.columns.count)・行 \(model.state.totalRowCount)")
            Spacer()
            Button("更新") { Task { await model.perform(.refresh) } }
        }
    }

    /// iOSのtable領域内だけを縦横scroll可能にします。
    private var tableArea: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("#").frame(width: 52, alignment: .leading)
                    ForEach(Array(model.state.columns.enumerated()), id: \.offset) { _, column in
                        Text(column.name).bold().frame(width: 180, alignment: .leading)
                    }
                }
                Divider()
                ForEach(model.state.rows) { row in
                    HStack(spacing: 0) {
                        Text(String(row.id + 1)).frame(width: 52, alignment: .leading)
                        ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                            Button(value.cellText) { Task { await model.perform(.openCell(rowID: row.id, columnIndex: index)) } }
                                .buttonStyle(.plain)
                                .lineLimit(1)
                                .frame(width: 180, alignment: .leading)
                                .accessibilityLabel("行 \(row.id + 1)、\(model.state.columns[index].name)、\(value.storageClassName)、\(value.cellText)")
                        }
                    }
                    Divider()
                }
                if model.state.hasNextPage {
                    Button("次のpageを読み込む") { Task { await model.perform(.loadNextPage) } }
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// cell完全値sheetです。
    private var detailSheet: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let detail = model.state.cellDetail {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("行 \(detail.rowNumber)・\(detail.columnName)").font(.headline)
                        Text(detail.storageClassName)
                        Text(detail.fullValue).textSelection(.enabled).monospaced()
                    }.padding()
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { Task { await model.perform(.closeCell) } } } }
        }
    }

    /// source Picker Bindingです。
    private var sourceSelection: Binding<DevelopmentDatabaseSource?> {
        Binding(get: { model.state.selectedSource }, set: { value in if let value { Task { await model.perform(.selectSource(value)) } } })
    }

    /// target Picker Bindingです。
    private var targetSelection: Binding<DevelopmentDatabaseTarget?> {
        Binding(get: { model.state.selectedTarget }, set: { value in if let value { Task { await model.perform(.selectTarget(value)) } } })
    }

    /// detail Stateをsheet Bindingへ変換します。
    private var detailPresented: Binding<Bool> {
        Binding(get: { model.state.cellDetail != nil }, set: { shown in if !shown { Task { await model.perform(.closeCell) } } })
    }

    /// 現在読込中かを返します。
    private var isLoading: Bool {
        switch model.state.loadState {
        case .loadingSchema, .loadingTable, .loadingNextPage: true
        default: false
        }
    }
}
#endif
#endif

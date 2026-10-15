import SwiftUI
import AppKit
import Core

struct HistoryView: View {
    @Bindable var viewModel: HistoryViewModel
    @State private var showingClearAllConfirm = false

    private static let dateFormat: Date.FormatStyle = Date.FormatStyle(
        date: .abbreviated,
        time: .shortened
    ).locale(Locale(identifier: "pt-BR"))

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.entries.isEmpty {
                emptyState
            } else {
                table
            }
        }
        .navigationTitle(HistoryStrings.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showingClearAllConfirm = true
                } label: {
                    Label(HistoryStrings.clearAll, systemImage: "trash")
                }
                .disabled(viewModel.entries.isEmpty)
            }
        }
        .searchable(
            text: $viewModel.query,
            placement: .toolbar,
            prompt: Text(HistoryStrings.searchPlaceholder)
        )
        .confirmationDialog(
            HistoryStrings.clearAllConfirmTitle,
            isPresented: $showingClearAllConfirm,
            titleVisibility: .visible
        ) {
            Button(HistoryStrings.clearAllConfirmOK, role: .destructive) {
                Task { await viewModel.clearAll() }
            }
            Button(HistoryStrings.clearAllConfirmCancel, role: .cancel) {}
        } message: {
            Text(HistoryStrings.clearAllConfirmMessage)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)
            Text(HistoryStrings.empty)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var table: some View {
        Table(viewModel.filteredEntries) {
            TableColumn(HistoryStrings.columnWhen) { entry in
                Text(entry.createdAt, format: Self.dateFormat)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 150, max: 170)

            TableColumn(HistoryStrings.columnMode) { entry in
                ModeBadge(mode: entry.mode)
            }
            .width(min: 80, ideal: 88, max: 96)

            TableColumn(HistoryStrings.columnApp) { entry in
                HStack(spacing: 6) {
                    Image(nsImage: AppIconResolver.icon(forBundleID: entry.sourceApp))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(AppIconResolver.displayName(forBundleID: entry.sourceApp))
                        .lineLimit(1)
                }
            }
            .width(min: 110, ideal: 140, max: 180)

            TableColumn(HistoryStrings.columnText) { entry in
                Text(entry.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .help(entry.text)
            }
            // Capped neighbours leave the remaining width to the text.
            .width(min: 200, ideal: 600)

            TableColumn(HistoryStrings.columnActions) { entry in
                HStack(spacing: 6) {
                    Button {
                        viewModel.copy(entry)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help(HistoryStrings.copy)

                    Button {
                        Task { await viewModel.repaste(entry) }
                    } label: {
                        Image(systemName: "arrow.uturn.left")
                    }
                    .help(HistoryStrings.repaste)

                    Button(role: .destructive) {
                        Task { await viewModel.delete(id: entry.id) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help(HistoryStrings.delete)
                }
                .buttonStyle(.borderless)
                .contextMenu {
                    Button(HistoryStrings.copy) { viewModel.copy(entry) }
                    Button(HistoryStrings.repaste) {
                        Task { await viewModel.repaste(entry) }
                    }
                    Divider()
                    Button(HistoryStrings.delete, role: .destructive) {
                        Task { await viewModel.delete(id: entry.id) }
                    }
                }
            }
            .width(min: 90, ideal: 96, max: 110)
        }
    }
}

private struct ModeBadge: View {
    let mode: HistoryMode

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
            .accessibilityLabel(label)
    }

    private var label: String {
        switch mode {
        case .refine: return HistoryStrings.modeRefine
        case .translate: return HistoryStrings.modeTranslate
        case .raw: return HistoryStrings.modeRaw
        }
    }

    private var background: Color {
        switch mode {
        case .refine: return Color.accentColor.opacity(0.18)
        case .translate: return Color.purple.opacity(0.18)
        case .raw: return Color.gray.opacity(0.18)
        }
    }

    private var foreground: Color {
        switch mode {
        case .refine: return Color.accentColor
        case .translate: return .purple
        case .raw: return .secondary
        }
    }
}

import SwiftUI

/// A destination for a move operation (a project or a team).
struct MoveTarget: Identifiable, Hashable {
    let id: String
    let name: String
}

/// A modal picker of move destinations. Reused to move files (destination = projects) and
/// projects (destination = teams). Loads its list lazily; on selection it performs the move,
/// then dismisses so the caller can refresh.
struct MoveSheet: View {
    let title: LocalizedStringKey
    /// Alert title when `onSelect` fails — overridable for reuses that aren't a "move"
    /// (e.g. importing a template into a project). Declared before the closures so existing
    /// trailing-closure call sites keep compiling.
    var failureTitle: LocalizedStringKey = "Couldn’t move"
    /// Loads the available destinations (already filtered to exclude the current location).
    let load: () async throws -> [MoveTarget]
    /// Performs the move to the chosen destination.
    let onSelect: (MoveTarget) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var isMoving = false
    @State private var moveError: String?

    private enum Phase {
        case loading
        case ready([MoveTarget])
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(isMoving)
                    }
                }
                .alert(failureTitle, isPresented: moveErrorAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(moveError ?? "")
                }
        }
        .task { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            LoadingView(message: "Loading…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await reload() } }
        case .ready(let targets):
            if targets.isEmpty {
                EmptyStateView(title: "No destinations available", icon: .folder)
            } else {
                ScrollView {
                    PenpotCard {
                        ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                            Button { Task { await select(target) } } label: {
                                PenpotCardRow(showsChevron: false) {
                                    Text(target.name)
                                } trailing: {
                                    if isMoving { ProgressView() }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isMoving)
                            if index < targets.count - 1 {
                                PenpotCardDivider()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .penpotPageBackground()
            }
        }
    }

    private var moveErrorAlert: Binding<Bool> {
        Binding(get: { moveError != nil }, set: { if !$0 { moveError = nil } })
    }

    private func reload() async {
        phase = .loading
        do {
            phase = .ready(try await load())
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func select(_ target: MoveTarget) async {
        guard !isMoving else { return }
        isMoving = true
        do {
            try await onSelect(target)
            dismiss()
        } catch {
            moveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isMoving = false
        }
    }
}

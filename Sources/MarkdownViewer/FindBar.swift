import SwiftUI

/// The find bar shown above the page while searching. Pure UI — every action
/// goes through `FindController`.
struct FindBar: View {
    @ObservedObject var find: FindController
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find", text: $find.query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .frame(minWidth: 140, idealWidth: 220, maxWidth: 320)
                .onSubmit { find.findNext() }

            Toggle(isOn: $find.caseSensitive) {
                Text("Aa").font(.system(size: 11, weight: .semibold))
            }
            .toggleStyle(.button)
            .help("Match case")

            Button { find.findPrevious() } label: { Image(systemName: "chevron.up") }
                .disabled(find.query.isEmpty)
                .help("Find previous (⇧⌘G)")

            Button { find.findNext() } label: { Image(systemName: "chevron.down") }
                .disabled(find.query.isEmpty)
                .help("Find next (⌘G)")

            Text(find.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()

            Spacer(minLength: 8)

            // Escape closes the bar and returns focus to the page.
            Button("Done") { find.close() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
        // Opening the bar (and every further ⌘F) puts the keyboard in the search
        // field; the hop lets SwiftUI finish installing the field first.
        .onAppear { focusField() }
        .onChange(of: find.focusRequest) { _ in focusField() }
        // Search as you type, and re-run when the case toggle flips.
        .onChange(of: find.query) { _ in find.refresh() }
        .onChange(of: find.caseSensitive) { _ in find.refresh() }
    }

    private func focusField() {
        DispatchQueue.main.async { fieldFocused = true }
    }
}

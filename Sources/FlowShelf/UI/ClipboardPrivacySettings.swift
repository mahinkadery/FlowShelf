import SwiftUI

struct ClipboardPrivacySettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var newType = ""
    @State private var pendingType = ""
    @State private var showingConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Built-in protection stays on", systemImage: "lock.shield")
                .font(.system(size: 12, weight: .semibold))
            Text("FlowShelf skips copies marked confidential, temporary or automatically generated, including recognized legacy markers. Apps must supply these markers; this cannot detect every password.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            DisclosureGroup("Built-in type names") {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(ClipboardPrivacyRules.builtInTypes, id: \.self) { type in
                        Text(type).font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            }
            .font(.system(size: 11))
            Divider()
            Text("Additional ignored types")
                .font(.system(size: 12, weight: .semibold))
            Text("Advanced: enter an exact, case-sensitive clipboard type supplied by an app—not its app name or bundle ID. If any item has that type, the entire new copy is skipped. Existing history and manual file drops are unchanged.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(settings.ignoredClipboardTypes, id: \.self) { type in
                HStack(alignment: .top, spacing: 8) {
                    Text(type).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        settings.ignoredClipboardTypes.removeAll { $0 == type }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove ignored type \(type)")
                    .help("Allow future copies of this type; built-in rules still apply")
                }
            }
            HStack {
                TextField("com.example.private-clipboard", text: $newType)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Clipboard type to ignore")
                    .onSubmit { prepareAddition() }
                Button("Add…") { prepareAddition() }
                    .disabled(ClipboardPrivacyRules.normalized(newType).isEmpty)
            }
            .controlSize(.small)
            if let errorMessage {
                Text(errorMessage).font(.system(size: 11)).foregroundStyle(.red)
            }
            Text("Common types such as public.utf8-plain-text can block almost all text capture. Remove a custom rule to undo it; skipped copies are not recovered.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(12).raisedCard()
        .onChange(of: newType) { _, _ in errorMessage = nil }
        .alert("Ignore copies containing this type?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Add ignored type") {
                if let message = ClipboardPrivacyRules.validationMessage(for: pendingType, existing: settings.ignoredClipboardTypes) {
                    errorMessage = message
                } else {
                    settings.ignoredClipboardTypes.append(pendingType)
                    newType = ""
                    errorMessage = nil
                }
            }
        } message: {
            Text("\(pendingType)\n\nFlowShelf will skip the entire new copy whenever this exact type is present, even if the copy also contains other formats. This does not remove existing history or change what you can paste into other apps.")
        }
    }

    private func prepareAddition() {
        if let message = ClipboardPrivacyRules.validationMessage(for: newType, existing: settings.ignoredClipboardTypes) {
            errorMessage = message
            return
        }
        pendingType = ClipboardPrivacyRules.normalized(newType)
        showingConfirmation = true
    }
}

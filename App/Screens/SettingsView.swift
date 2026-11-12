import PhtofxrCore
import SwiftUI

/// Which filename formats count, the rules for the buckets, and the diagnostics.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(FilenameFormat.catalog) { format in
                        Toggle(isOn: Binding(
                            get: { model.settings.isEnabled(format) },
                            set: { model.setFormat(format, enabled: $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.displayName)
                                Text(verbatim: format.examples.first ?? "")
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("format.\(format.id)")
                    }
                } header: {
                    Text("Filename formats")
                } footer: {
                    Text("Phtofxr tries the formats from top to bottom and uses the first that fits.")
                }

                Section {
                    Stepper(value: Binding(
                        get: { model.settings.minimumYear },
                        set: { model.settings.minimumYear = $0 }
                    ), in: 1900...2030) {
                        LabeledContent("Minimum year") {
                            Text(verbatim: String(model.settings.minimumYear))
                        }
                    }
                    LabeledContent("Already correct", value: String(localized: "less than a day apart"))
                    LabeledContent("Uncertain", value: String(localized: "a day to a week apart"))
                    LabeledContent("Certain", value: String(localized: "more than a week apart"))
                } header: {
                    Text("Rules")
                } footer: {
                    Text("A proposal is only certain when the date in Photos looks filled in: the moment of import, a day full of photos whose names point elsewhere, or a camera's reset date.")
                }

                Section {
                    NavigationLink("Diagnostics") {
                        DiagnoseView()
                    }
                    .accessibilityIdentifier("diagnostics")
                } footer: {
                    Text("Phtofxr works entirely on this device. It never connects to the internet.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("done")
                }
            }
        }
    }
}

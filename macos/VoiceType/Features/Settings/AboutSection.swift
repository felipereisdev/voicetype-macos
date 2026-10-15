import SwiftUI

struct AboutSection: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(SettingsStrings.aboutVersion) {
                    Text(version).monospacedDigit()
                }
                LabeledContent(SettingsStrings.aboutBuild) {
                    Text(build).monospacedDigit()
                }
            }
            Section {
                Link(SettingsStrings.aboutLicense,
                     destination: URL(string: "https://github.com/macsilva/voicetype/blob/main/LICENSE")!)
                Link(SettingsStrings.aboutGitHub,
                     destination: URL(string: "https://github.com/macsilva/voicetype")!)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsStrings.sidebarAbout)
    }
}

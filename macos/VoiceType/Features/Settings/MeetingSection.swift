import AppKit
import SwiftUI
import Core

struct MeetingSection: View {
    let snapshot: ConfigStoreSnapshot
    /// Aliases are edited as free text, so the catalog lives in a local draft
    /// and is saved only while it validates (a mid-typing "a, " would
    /// otherwise round-trip to "a").
    @State private var draft: [OrgDraft] = []

    private var detectedCLI: String {
        ClaudeCLISummarizer.locate(configured: nil)?.path ?? SettingsStrings.meetingCLINotFound
    }

    var body: some View {
        Form {
            Section(SettingsStrings.meetingNotesHeader) {
                TextField(SettingsStrings.meetingNotesFolderLabel, text: Binding(
                    get: { snapshot.config.meetingNotesFolder },
                    set: { v in Task { await snapshot.update { $0.meetingNotesFolder = v } } }
                ))
                HStack {
                    Button(SettingsStrings.meetingChooseFolder) { chooseFolder() }
                    Button(SettingsStrings.meetingShowInFinder) {
                        let path = (snapshot.config.meetingNotesFolder as NSString).expandingTildeInPath
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
                TextField(SettingsStrings.meetingCLIPathLabel, text: Binding(
                    get: { snapshot.config.claudeCLIPath ?? "" },
                    set: { v in
                        let trimmed = v.trimmingCharacters(in: .whitespaces)
                        let value: String? = trimmed.isEmpty ? nil : v
                        Task { await snapshot.update { $0.claudeCLIPath = value } }
                    }
                ), prompt: Text(detectedCLI))
            }

            Section(SettingsStrings.meetingCaptureHeader) {
                Picker(SettingsStrings.meetingDetectionLabel, selection: Binding(
                    get: { snapshot.config.meetingDetectionMode },
                    set: { v in Task { await snapshot.update { $0.meetingDetectionMode = v } } }
                )) {
                    ForEach(SettingsStrings.meetingDetectionOptions, id: \.id) { Text($0.label).tag($0.id) }
                }
                Stepper(value: Binding(
                    get: { snapshot.config.meetingAudioRetentionDays },
                    set: { v in
                        let clamped = max(v, 0)
                        Task { await snapshot.update { $0.meetingAudioRetentionDays = clamped } }
                    }
                ), in: 0...365) {
                    LabeledContent(SettingsStrings.meetingRetentionLabel) {
                        Text(SettingsStrings.meetingRetentionValue(snapshot.config.meetingAudioRetentionDays))
                            .monospacedDigit()
                    }
                }
                Text(SettingsStrings.meetingRetentionHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(SettingsStrings.meetingOrgsHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(SettingsStrings.meetingOrgsHeader)
            }

            ForEach($draft) { $org in
                Section {
                    HStack {
                        Image(systemName: "building.2")
                            .foregroundStyle(.secondary)
                        TextField(SettingsStrings.meetingOrgName, text: $org.name,
                                  prompt: Text(SettingsStrings.meetingOrgName))
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                            .font(.headline)
                        Button(role: .destructive) {
                            draft.removeAll { $0.id == org.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(SettingsStrings.meetingRemoveOrg)
                    }
                    TextField(SettingsStrings.meetingAliasesLabel, text: $org.aliases,
                              prompt: Text(SettingsStrings.meetingAliasesPrompt))
                    ForEach($org.clients) { $client in
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.square")
                                .foregroundStyle(.secondary)
                            TextField(SettingsStrings.meetingClientName, text: $client.name,
                                      prompt: Text(SettingsStrings.meetingClientName))
                                .labelsHidden()
                                .multilineTextAlignment(.leading)
                                .frame(width: 160)
                            TextField(SettingsStrings.meetingAliasesLabel, text: $client.aliases,
                                      prompt: Text(SettingsStrings.meetingAliasesLabel))
                                .labelsHidden()
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                org.clients.removeAll { $0.id == client.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(SettingsStrings.meetingRemoveClient)
                        }
                        .padding(.leading, 12)
                    }
                    Button {
                        org.clients.append(ClientDraft())
                    } label: {
                        Label(SettingsStrings.meetingAddClient, systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 12)
                }
            }

            Section {
                Button {
                    draft.append(OrgDraft())
                } label: {
                    Label(SettingsStrings.meetingAddOrg, systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                if !draft.contains(where: { $0.name.trimmingCharacters(in: .whitespaces) == MeetingOrg.fallbackName }) {
                    Text(SettingsStrings.meetingFallbackMissing)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                ForEach(MeetingOrg.validationIssues(draft.map(\.org)), id: \.self) { issue in
                    Text(issue).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsStrings.sidebarMeetings)
        .onAppear { draft = snapshot.config.meetingOrgs.map(OrgDraft.init) }
        .onChange(of: draft) { _, next in
            let orgs = next.map(\.org)
            guard MeetingOrg.validationIssues(orgs).isEmpty, orgs != snapshot.config.meetingOrgs else { return }
            Task { await snapshot.update { $0.meetingOrgs = orgs } }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: (snapshot.config.meetingNotesFolder as NSString).expandingTildeInPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = NSHomeDirectory()
        let path = url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
        Task { await snapshot.update { $0.meetingNotesFolder = path } }
    }
}

private struct ClientDraft: Identifiable, Equatable {
    let id = UUID()
    var name = ""
    var aliases = ""

    init() {}
    init(_ c: MeetingClient) { name = c.name; aliases = c.aliases.joined(separator: ", ") }

    var client: MeetingClient {
        MeetingClient(name: name.trimmingCharacters(in: .whitespaces), aliases: MeetingOrg.parseAliases(aliases))
    }
}

private struct OrgDraft: Identifiable, Equatable {
    let id = UUID()
    var name = ""
    var aliases = ""
    var clients: [ClientDraft] = []

    init() {}
    init(_ o: MeetingOrg) {
        name = o.name
        aliases = o.aliases.joined(separator: ", ")
        clients = o.clients.map(ClientDraft.init)
    }

    var org: MeetingOrg {
        MeetingOrg(name: name.trimmingCharacters(in: .whitespaces),
                   aliases: MeetingOrg.parseAliases(aliases),
                   clients: clients.map(\.client))
    }
}

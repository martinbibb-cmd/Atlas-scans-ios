import SwiftUI

struct WorkspacePickerView: View {
    let profile: AtlasUserProfileV1?
    let workspaces: [AtlasWorkspaceV1]
    let selectedWorkspace: AtlasWorkspaceV1?
    let onSelectWorkspace: (AtlasWorkspaceV1) -> Void
    let onSignOut: () -> Void

    var body: some View {
        List {
            if let profile {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName ?? "Atlas Engineer")
                            .font(.headline)
                        if let email = profile.email {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Signed in")
                }
            }

            Section("Workspaces") {
                ForEach(workspaces) { workspace in
                    Button {
                        onSelectWorkspace(workspace)
                    } label: {
                        HStack {
                            Text(workspace.name)
                            Spacer()
                            if selectedWorkspace?.id == workspace.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Choose Workspace")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Sign Out", role: .destructive, action: onSignOut)
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        WorkspacePickerView(
            profile: AtlasUserProfileV1(id: "1", email: "engineer@atlas-phm.uk", displayName: "Atlas Engineer"),
            workspaces: [
                AtlasWorkspaceV1(id: "w1", name: "Primary Workspace"),
                AtlasWorkspaceV1(id: "w2", name: "Training Workspace")
            ],
            selectedWorkspace: nil,
            onSelectWorkspace: { _ in },
            onSignOut: {}
        )
    }
}
#endif

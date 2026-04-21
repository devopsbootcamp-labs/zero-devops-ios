import SwiftUI

struct ProfileView: View {

    @EnvironmentObject private var container: AppContainer
    @StateObject private var vm = ProfileViewModel()

    var body: some View {
        NavigationView {
            List {
                // User info
                if let p = vm.profile {
                    Section("User") {
                        ProfileRow(label: "Name",      value: p.name ?? [(p.givenName ?? ""), (p.familyName ?? "")].filter { !$0.isEmpty }.joined(separator: " "))
                        ProfileRow(label: "Email",     value: p.email ?? "—")
                        ProfileRow(label: "User ID",   value: p.sub   ?? "—")
                    }
                    Section("Tenant / Account") {
                        ProfileRow(label: "Tenant ID",         value: p.tenantId        ?? "—")
                        ProfileRow(label: "Account ID",        value: p.accountId       ?? "—")
                        ProfileRow(label: "Cloud Account ID",  value: p.cloudAccountId  ?? "—")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        container.logout()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .overlay { if vm.isLoading { ProgressView("Loading…") } }
            .task { await vm.load() }
        }
    }
}

private struct ProfileRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}

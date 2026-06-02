import SwiftUI

// Contacts tab root. State machine:
//   • notDetermined  → request permission on appear
//   • denied/restricted → permission gate (Open Settings)
//   • authorized/limited → NavigationStack { ContactsDashboardView }
struct ContactsView: View {
    @State private var service = ContactsService()
    @State private var path = NavigationPath()
    @Environment(TabChrome.self) private var chrome: TabChrome?

    var body: some View {
        Group {
            switch service.authStatus {
            case .notDetermined:
                loadingView
            case .denied, .restricted:
                permissionGate
            case .authorized, .limited:
                NavigationStack(path: $path) {
                    ContactsDashboardView(service: service)
                }
                .onChange(of: path) { _, newPath in
                    // Tell RootView to hide the tab bar + banner while a detail
                    // screen is open (detail screens have their own bottom bar).
                    chrome?.contactsDepth = newPath.count
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: service.authStatus)
        .task {
            if service.authStatus == .notDetermined {
                await service.requestAccess()
            }
        }
    }

    private var loadingView: some View {
        ZStack {
            AppColor.surfaceBackground.ignoresSafeArea()
            ProgressView()
                .tint(AppColor.brandPrimary)
                .scaleEffect(1.2)
        }
    }

    private var permissionGate: some View {
        ZStack {
            AppColor.surfaceBackground.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 64))
                    .foregroundStyle(AppColor.brandPrimary)
                Text("Contacts access required")
                    .font(.custom("Inter-Bold", size: 22))
                    .foregroundStyle(AppColor.textPrimary)
                Text("iCleaner reads your contacts to find duplicates, incomplete entries, and back them up safely.")
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(action: { service.opensSettings() }) {
                    Text("Open Settings")
                        .font(.custom("Inter-Bold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppColor.brandPrimary)
                        )
                }
                .padding(.horizontal, 32)
            }
        }
    }
}

#Preview {
    ContactsView()
}

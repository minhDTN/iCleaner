import SwiftUI
import LibEarnMoneyIOS

// Figma `2012:4599` (Backups). Header = back + "Backups" + "N Backups" subtitle.
// During a backup an "Active Progress State" card shows. Each saved backup is a
// clean info card: lavender icon bucket + date (Medium 17) + "N contacts"
// (Regular 15) + time on the right. Tap a row to Restore / Delete. Bottom CTA
// "Create backup" (blue, radius 12).
struct ContactsBackupsView: View {
    @Bindable var service: ContactsService

    @State private var backups: [BackupFile] = []
    @State private var creating: Bool = false
    @State private var restoring: BackupFile?
    @State private var selectedBackup: BackupFile?
    @State private var actionError: String?
    @State private var lastResult: String?
    @State private var showPaywall: Bool = false
    @State private var shareURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            ContactsDetailHeader(title: L("contacts.backups.title"), subtitle: L("contacts.backups.count", backups.count))
            ZStack(alignment: .bottom) {
                AppColor.surfaceBackground.ignoresSafeArea(edges: .bottom)

                ScrollView {
                    VStack(spacing: 24) {
                        if creating { progressCard }
                        if backups.isEmpty && !creating {
                            emptyView
                        } else {
                            VStack(spacing: 16) {
                                ForEach(backups) { backup in
                                    backupRow(backup)
                                }
                            }
                        }
                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)  // room for the CTA
                }

                createButton
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
        .task {
            FlowGate.showStartAd()   // ad on feature entry (free users)
            backups = service.fetchBackups()
        }
        .confirmationDialog(
            selectedBackup.map { L("contacts.backups.item") + " • " + L("contacts.count", $0.contactCount) } ?? L("contacts.backups.item"),
            isPresented: Binding(get: { selectedBackup != nil }, set: { if !$0 { selectedBackup = nil } }),
            titleVisibility: .visible
        ) {
            if let backup = selectedBackup {
                Button(L("contacts.backups.restore", backup.contactCount)) { Task { await performRestore(backup) } }
                Button(L("contacts.backups.share")) { shareURL = backup.url }
                Button(L("contacts.backups.delete"), role: .destructive) {
                    service.deleteBackup(backup)
                    backups.removeAll { $0.id == backup.id }
                }
            }
            Button(L("common.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { BackupShareSheet(url: shareURL) }
        }
        .alert(L("contacts.backups.errorTitle"), isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
        .alert(L("contacts.backups.restoredTitle"), isPresented: Binding(
            get: { lastResult != nil },
            set: { if !$0 { lastResult = nil } }
        )) {
            Button("OK", role: .cancel) { lastResult = nil }
        } message: { Text(lastResult ?? "") }
    }

    // MARK: - Rows

    private func backupRow(_ backup: BackupFile) -> some View {
        let busy = restoring?.id == backup.id
        return HStack(spacing: 16) {
            ZStack {
                Circle().fill(Color(hex: 0xF2F3FF)).frame(width: 48, height: 48)
                Image("Contacts/ic_backup_doc")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 19, height: 21)
                    .foregroundStyle(AppColor.brandPrimary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dateString(backup.createdAt))
                    .font(.custom("Inter-Medium", size: 17))
                    .foregroundStyle(Color(hex: 0x131B2E))
                Text(L("contacts.count", backup.contactCount))
                    .font(.custom("Inter-Regular", size: 15))
                    .foregroundStyle(Color(hex: 0x434655))
            }
            Spacer(minLength: 8)
            if busy {
                ProgressView().tint(AppColor.brandPrimary)
            } else {
                Text(Self.timeString(backup.createdAt))
                    .font(.custom("Inter-Regular", size: 15))
                    .foregroundStyle(Color(hex: 0x434655))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.brandPrimary, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !busy { selectedBackup = backup } }
    }

    private var progressCard: some View { BackupProgressCard() }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.brandPrimary)
            Text(L("contacts.backups.emptyTitle"))
                .font(.custom("Inter-Bold", size: 20))
                .foregroundStyle(AppColor.textPrimary)
            Text(L("contacts.backups.emptyBody"))
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 64)
    }

    private var createButton: some View {
        Button(action: { Task { await performCreate() } }) {
            HStack(spacing: 8) {
                if creating {
                    ProgressView().tint(.white).scaleEffect(0.9)
                } else {
                    Image("Contacts/ic_backup_add")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                Text(L("contacts.backups.create"))
                    .font(.custom("Inter-SemiBold", size: 13))
                    .tracking(13 * 0.05)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColor.brandPrimary))
        }
        .buttonStyle(.plain)
        .disabled(creating)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .background(
            AppColor.surfaceBackground
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color(hex: 0xC3C6D7)).frame(height: 1)
                }
        )
    }

    // MARK: - Format

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    private static func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: - Actions

    private func performCreate() async {
        if FlowGate.requiresPaywall { showPaywall = true; return }   // final step → paywall for free
        creating = true
        defer { creating = false }
        do {
            let file = try await service.createBackup()
            backups.insert(file, at: 0)
            fireActionInterstitial()
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }

    private func performRestore(_ file: BackupFile) async {
        if FlowGate.requiresPaywall { showPaywall = true; return }   // final step → paywall for free
        restoring = file
        defer { restoring = nil }
        do {
            let count = try await service.restore(from: file)
            lastResult = L("contacts.backups.restoredMsg", count)
            fireActionInterstitial()
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }

    private func fireActionInterstitial() {
        FlowGate.showInterstitial()   // only if cached — never block on a loading spinner
    }
}

// "Backing up contacts… N%" card (Figma 2012:4599): title + brand-blue percent on
// the right, with a determinate fill bar. The vCard write isn't incrementally
// measurable, so the percent ramps to ~92% while writing and the card is removed
// when the backup completes (a quick op for most libraries).
private struct BackupProgressCard: View {
    @State private var progress: Double = 0.05

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Image("Contacts/ic_backup_cloud")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 16)
                        .foregroundStyle(AppColor.brandPrimary)
                    Text(L("contacts.backups.backing"))
                        .font(.custom("Inter-SemiBold", size: 15))
                        .foregroundStyle(Color(hex: 0x131B2E))
                }
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.custom("Inter-Bold", size: 15))
                    .foregroundStyle(AppColor.brandPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xDAE2FD))
                    Capsule().fill(AppColor.brandPrimary)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 8)
            .padding(.top, 4)
            .animation(.linear(duration: 0.1), value: progress)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0x004AC6, alpha: 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: 0xC3C6D7), lineWidth: 1)
        )
        .onReceive(Timer.publish(every: 0.06, on: .main, in: .common).autoconnect()) { _ in
            if progress < 0.92 { progress = min(0.92, progress + 0.025) }
        }
    }
}

// Exports a backup .vcf via the system share sheet (save to Files, AirDrop, etc.).
private struct BackupShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

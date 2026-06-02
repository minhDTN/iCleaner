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

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.surfaceBackground.ignoresSafeArea()

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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ContactsNavTitle(title: "Backups", subtitle: "\(backups.count) Backups")
            }
        }
        .task { backups = service.fetchBackups() }
        .confirmationDialog(
            selectedBackup.map { "Backup • \($0.contactCount) contacts" } ?? "Backup",
            isPresented: Binding(get: { selectedBackup != nil }, set: { if !$0 { selectedBackup = nil } }),
            titleVisibility: .visible
        ) {
            if let backup = selectedBackup {
                Button("Restore \(backup.contactCount) contacts") { Task { await performRestore(backup) } }
                Button("Delete backup", role: .destructive) {
                    service.deleteBackup(backup)
                    backups.removeAll { $0.id == backup.id }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Backup error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
        .alert("Restored", isPresented: Binding(
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
                Text("\(backup.contactCount) contacts")
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

    private var progressCard: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Image("Contacts/ic_backup_cloud")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 16)
                        .foregroundStyle(AppColor.brandPrimary)
                    Text("Backing up contacts…")
                        .font(.custom("Inter-SemiBold", size: 15))
                        .foregroundStyle(Color(hex: 0x131B2E))
                }
                Spacer()
            }
            IndeterminateBar()
                .frame(height: 8)
                .padding(.top, 4)
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
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.brandPrimary)
            Text("No backups yet")
                .font(.custom("Inter-Bold", size: 20))
                .foregroundStyle(AppColor.textPrimary)
            Text("Tap Create backup to save a snapshot of every contact as a vCard file on this device.")
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
                Text("Create backup")
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
        restoring = file
        defer { restoring = nil }
        do {
            let count = try await service.restore(from: file)
            lastResult = "Restored \(count) contact\(count == 1 ? "" : "s") from this backup."
            fireActionInterstitial()
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }

    private func fireActionInterstitial() {
        guard !PremiumGate.isPremium,
              let vc = AdHelpers.topViewController() else { return }
        AdManager.shared.showInterstitialAd(
            adUnitID: AdUnits.interContactsAction,
            from: vc,
            completion: nil
        )
    }
}

// Looping shimmer bar (track #DAE2FD + sliding brand-blue segment) shown while a
// backup is being written — honest indeterminate progress (the vCard write isn't
// incrementally measurable).
private struct IndeterminateBar: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0xDAE2FD))
                Capsule()
                    .fill(AppColor.brandPrimary)
                    .frame(width: w * 0.4)
                    .offset(x: phase * w * 1.4 - w * 0.4)
            }
            .clipShape(Capsule())
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
    }
}

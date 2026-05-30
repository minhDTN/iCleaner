import SwiftUI
import LibEarnMoneyIOS

// Figma `2012:4599` (Backups). History list of vCard files + "Create backup"
// CTA. Per-row swipe Delete + tap "Restore" to re-import all contacts in that
// backup. Interstitial fires after Create / Restore (premium-gated).
struct ContactsBackupsView: View {
    @Bindable var service: ContactsService

    @State private var backups: [BackupFile] = []
    @State private var creating: Bool = false
    @State private var restoring: BackupFile?
    @State private var actionError: String?
    @State private var lastResult: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.surfaceBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    if creating { backupInProgressCard }
                    if backups.isEmpty && !creating {
                        emptyView
                    } else {
                        VStack(spacing: 8) {
                            ForEach(backups) { backup in
                                BackupRow(
                                    backup: backup,
                                    busy: restoring?.id == backup.id,
                                    onRestore: { Task { await performRestore(backup) } },
                                    onDelete: {
                                        service.deleteBackup(backup)
                                        backups.removeAll { $0.id == backup.id }
                                    }
                                )
                            }
                        }
                    }
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            createButton
        }
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task { backups = service.fetchBackups() }
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

    // MARK: - Subviews

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

    private var backupInProgressCard: some View {
        HStack(spacing: 16) {
            ProgressView().tint(AppColor.brandPrimary).scaleEffect(1.2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Backing up contacts…")
                    .font(.custom("Inter-SemiBold", size: 14))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Writing vCard to local storage.")
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: 0xDBE1FF).opacity(0.6))
        )
    }

    private var createButton: some View {
        Button(action: { Task { await performCreate() } }) {
            HStack(spacing: 8) {
                if creating { ProgressView().tint(.white).scaleEffect(0.9) }
                Image(systemName: "plus")
                Text("Create backup")
            }
            .font(.custom("Inter-Bold", size: 16))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColor.brandPrimary)
                    .shadow(color: AppColor.brandPrimary.opacity(0.3), radius: 10, x: 0, y: 6)
            )
        }
        .disabled(creating)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
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
        guard !PermissionManager.shared.isPremium,
              let vc = AdHelpers.topViewController() else { return }
        AdManager.shared.showInterstitialAd(
            adUnitID: AdUnits.interContactsAction,
            from: vc,
            completion: nil
        )
    }
}

private struct BackupRow: View {
    let backup: BackupFile
    let busy: Bool
    var onRestore: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 18))
                .foregroundStyle(AppColor.brandPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(AppColor.brandPrimary.opacity(0.10)))

            VStack(alignment: .leading, spacing: 4) {
                Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.custom("Inter-SemiBold", size: 14))
                    .foregroundStyle(AppColor.textPrimary)
                Text(ByteCountFormatter.string(fromByteCount: Int64(backup.sizeBytes), countStyle: .file))
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Button(action: onRestore) {
                if busy { ProgressView().scaleEffect(0.7).tint(AppColor.brandPrimary) }
                else    { Text("Restore").font(.custom("Inter-SemiBold", size: 13)).foregroundStyle(AppColor.brandPrimary) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(AppColor.brandPrimary.opacity(0.10)))
            .disabled(busy)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.danger)
                    .frame(width: 32, height: 32)
            }
            .disabled(busy)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xE2E8F0), lineWidth: 1)
        )
    }
}

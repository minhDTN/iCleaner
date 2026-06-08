import SwiftUI

// Figma `2005:23659` (FAQ). Accordion list. Questions hard-authored from the
// Figma copy (the export only gave headlines without bodies — answers expanded
// here are plausible MVP copy; replace when content team ships final).
struct FAQView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<Int> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Each question is its own bordered box (Figma) — no big "FAQ"
                // heading above the list (the nav bar already says "FAQ").
                ForEach(FAQItem.all.indices, id: \.self) { idx in
                    FAQRow(
                        item: FAQItem.all[idx],
                        isExpanded: expanded.contains(idx),
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                if expanded.contains(idx) { expanded.remove(idx) }
                                else { expanded.insert(idx) }
                            }
                        }
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppColor.surfaceBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppColor.brandPrimary.opacity(0.2), lineWidth: 1)
                    )
                }

                contactCTA
                    .padding(.top, 12)

                // Banner ad sits between Contact Support and the Let's Start CTA.
                BannerAdView(adUnitID: AdUnits.bannerSetting)

                letsStartButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(AppColor.surfaceBackground)
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var contactCTA: some View {
        VStack(spacing: 8) {
            Text("Still have questions?")
                .font(.custom("Inter-SemiBold", size: 14))
                .foregroundStyle(Color(hex: 0x64748B))
            NavigationLink(destination: ContactView()) {
                Text("Contact Support")
                    .font(.custom("Inter-Bold", size: 14))
                    .foregroundStyle(AppColor.brandPrimary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // Bottom CTA — closes the FAQ so the user can get back to using the app.
    private var letsStartButton: some View {
        Button(action: { dismiss() }) {
            Text(L("lang.start"))
                .font(.custom("Inter-Bold", size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColor.brandPrimary)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct FAQItem {
    let question: String
    let answer: String

    static let all: [FAQItem] = [
        .init(question: "How does Cleaner scan my photo library?",
              answer: "Cleaner runs on-device: it groups similar photos by capture time and orientation, then optionally compares Vision feature prints to confirm visual similarity. No photo ever leaves your phone."),
        .init(question: "Are my photos uploaded anywhere?",
              answer: "Never. All scanning, comparison and cleanup happens on-device. We don't have servers that ever see your library."),
        .init(question: "Is Cleaner safe?",
              answer: "Yes. Deletes go through the standard iOS Photos APIs, so iOS shows you a final confirmation and moves deleted items to Recently Deleted for 30 days. You can always restore them from Photos."),
        .init(question: "What are \"Similar\" photos?",
              answer: "Photos taken within a short time window of each other that look alike (burst shots, retakes, near-identical scenes)."),
        .init(question: "How does Cleaner choose the best photo?",
              answer: "For the MVP, the earliest photo in each burst is marked Best Match. A future update will compare sharpness and file size to pick the highest quality."),
        .init(question: "Should I review Cleaner's suggestions?",
              answer: "Yes — Cleaner pre-selects every duplicate except the Best Match, but you can deselect any photo before tapping Delete."),
        .init(question: "How do I cancel my subscription?",
              answer: "Open the iOS Settings app → tap your name at the top → Subscriptions → iCleaner → Cancel. Your premium access continues until the end of the current billing period."),
        .init(question: "Can I use Cleaner on multiple devices?",
              answer: "Yes — your subscription is tied to your Apple ID. On another iPhone or iPad signed in to the same Apple ID, tap Restore Purchase in Settings."),
        .init(question: "Why don't I see more free space after cleaning?",
              answer: "Deleted photos move to Recently Deleted in Photos for 30 days. To free space immediately, open Photos → Recently Deleted → Select → Delete All."),
    ]
}

private struct FAQRow: View {
    let item: FAQItem
    let isExpanded: Bool
    var onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(item.question)
                    .font(.custom("Inter-SemiBold", size: 15))
                    .foregroundStyle(Color(hex: 0x0F172A))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x64748B))
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }

            if isExpanded {
                Text(item.answer)
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color(hex: 0x64748B))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .lineSpacing(22 - 14)
            }
        }
    }
}

#Preview {
    NavigationStack { FAQView() }
}

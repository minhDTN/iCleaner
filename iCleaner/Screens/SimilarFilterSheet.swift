import SwiftUI

// Figma `2005:23515` (filter). Bottom sheet, white bg, radius 32 top, drag
// indicator 40×4 #E2E8F0. Header "Filter" (Inter Bold 20/28 #0F172A) +
// "Clear All" (Inter SemiBold 14/20 #3B82F6). 3 pill-row sections:
// DATE RANGE / SORT BY SIZE / SOURCE (Inter Bold 12 ALL CAPS LS 10% #94A3B8).
// Apply CTA: blue #3B82F6, white text, 335×56, radius 16, blue-500 0.2 shadow.
struct SimilarFilterSheet: View {
    @Binding var filter: SimilarFilter
    var onApply: () -> Void
    var onClear: () -> Void

    var body: some View {
        // Filter options scroll (so a small device with wrapping pills never cuts
        // anything off); the Apply button is pinned to the very bottom via
        // safeAreaInset so it always hugs the bottom edge — no dead space below it.
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Capsule()
                    .fill(Color(hex: 0xE2E8F0))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)   // centered drag handle

                HStack {
                    Text(L("filter.title"))
                        .font(.custom("Inter-Bold", size: 20))
                        .foregroundStyle(Color(hex: 0x0F172A))
                    Spacer()
                    Button(action: onClear) {
                        Text(L("filter.clearAll"))
                            .font(.custom("Inter-SemiBold", size: 14))
                            .foregroundStyle(Color(hex: 0x3B82F6))
                    }
                }
                .padding(.horizontal, 24)

                pillSection(title: L("filter.dateRange")) {
                    PillFlow(spacing: 12, lineSpacing: 12) {
                        ForEach(SimilarFilter.DateRange.allCases, id: \.self) { opt in
                            FilterPill(label: L(opt.labelKey), isActive: filter.dateRange == opt) {
                                filter.dateRange = opt
                            }
                        }
                    }
                }
                pillSection(title: L("filter.sortBySize")) {
                    PillFlow(spacing: 12, lineSpacing: 12) {
                        ForEach(SimilarFilter.SortBySize.allCases, id: \.self) { opt in
                            FilterPill(label: L(opt.labelKey), isActive: filter.sortBySize == opt) {
                                filter.sortBySize = opt
                            }
                        }
                    }
                }
                pillSection(title: L("filter.source")) {
                    PillFlow(spacing: 12, lineSpacing: 12) {
                        ForEach(SimilarFilter.Source.allCases, id: \.self) { opt in
                            FilterPill(label: L(opt.labelKey), isActive: filter.sources.contains(opt)) {
                                if filter.sources.contains(opt) {
                                    filter.sources.remove(opt)
                                } else {
                                    filter.sources.insert(opt)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)   // no bounce/scroll when it all fits
        .safeAreaInset(edge: .bottom) {
            Button(action: onApply) {
                Text(L("filter.apply"))
                    .font(.custom("Inter-Bold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: 0x3B82F6))
                            .shadow(color: Color(hex: 0x3B82F6).opacity(0.2), radius: 6, x: 0, y: 4)
                            .shadow(color: Color(hex: 0x3B82F6).opacity(0.2), radius: 15, x: 0, y: 10)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(AppColor.surfaceBackground)
        }
        // Fixed, compact height: snug on normal phones (Apply right under SOURCE),
        // and the options scroll on small phones so nothing is cut off.
        .presentationDetents([.height(430)])
        .presentationBackground(AppColor.surfaceBackground)
    }

    @ViewBuilder
    private func pillSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.custom("Inter-Bold", size: 12))
                .tracking(12 * 0.10)  // 10% letterSpacing from Figma
                .textCase(.uppercase)
                .foregroundStyle(Color(hex: 0x94A3B8))
                .padding(.horizontal, 24)
            content()
                .padding(.horizontal, 24)
        }
    }
}

private struct FilterPill: View {
    let label: String
    let isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                // Figma: Inter Medium 14, pill padding 10×24 (was 13 / 16 — too
                // narrow, leaving an oversized right margin).
                .font(.custom("Inter-Medium", size: 14))
                .foregroundStyle(isActive ? Color(hex: 0x3B82F6) : Color(hex: 0x64748B))
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(AppColor.surfaceBackground)
                )
                .overlay(
                    Capsule().stroke(isActive ? Color(hex: 0x3B82F6) : Color(hex: 0xE2E8F0), lineWidth: 1)
                )
        }
    }
}

// Left-aligned flowing layout: pills sit left-to-right and wrap to a new line
// when the row runs out of width — so long chips (e.g. "Screenshots") drop to the
// next line instead of overflowing/clipping at the screen edge.
private struct PillFlow: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0; y += rowHeight + lineSpacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0; y += rowHeight + lineSpacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading,
                      proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    StatefulPreviewWrapper(SimilarFilter.default) { binding in
        SimilarFilterSheet(filter: binding, onApply: {}, onClear: {})
            .frame(height: 510)
    }
}

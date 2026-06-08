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

    // The sheet hugs its content (Figma) — measure it and feed the height to the
    // detent so there's no dead space pushing the Apply button to the bottom.
    @State private var contentHeight: CGFloat = 520

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color(hex: 0xE2E8F0))
                .frame(width: 40, height: 4)

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

            VStack(alignment: .leading, spacing: 32) {
                pillSection(title: L("filter.dateRange")) {
                    HStack(spacing: 12) {
                        ForEach(SimilarFilter.DateRange.allCases, id: \.self) { opt in
                            FilterPill(label: L(opt.labelKey), isActive: filter.dateRange == opt) {
                                filter.dateRange = opt
                            }
                        }
                    }
                }
                pillSection(title: L("filter.sortBySize")) {
                    HStack(spacing: 12) {
                        ForEach(SimilarFilter.SortBySize.allCases, id: \.self) { opt in
                            FilterPill(label: L(opt.labelKey), isActive: filter.sortBySize == opt) {
                                filter.sortBySize = opt
                            }
                        }
                    }
                }
                pillSection(title: L("filter.source")) {
                    HStack(spacing: 12) {
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
        }
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(
            AppColor.surfaceBackground
                .overlay(GeometryReader { proxy in
                    Color.clear.preference(key: FilterSheetHeightKey.self, value: proxy.size.height)
                })
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .onPreferenceChange(FilterSheetHeightKey.self) { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
    }

    @ViewBuilder
    private func pillSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
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

// Reports the filter sheet's natural content height so the detent hugs it.
private struct FilterSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 520
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

#Preview {
    StatefulPreviewWrapper(SimilarFilter.default) { binding in
        SimilarFilterSheet(filter: binding, onApply: {}, onClear: {})
            .frame(height: 510)
    }
}

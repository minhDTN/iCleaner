import SwiftUI

// Reusable 6-digit passcode entry: dot indicator row + 3×4 numpad.
// Caller owns `entry` Binding and gets `onComplete(code)` when 6 digits collected.
//
// Figma `2010:2243` (create pass): 6 dots 16×16 border #94A3B8 2px radius 8,
// gap 24. Numpad: 72×72 circular buttons, #F8FAFC fill + #CBD5E1 stroke 2px,
// "1".."9" + "0" (bottom centre) + backspace (bottom right). Digits Inter Bold
// 28/42 #0F172A.
struct PasscodeKeypad: View {
    @Binding var entry: String
    var onComplete: (String) -> Void = { _ in }
    var maxLength: Int = 6

    var body: some View {
        VStack(spacing: 24) {
            dotsRow
            numpad
        }
    }

    private var dotsRow: some View {
        HStack(spacing: 24) {
            ForEach(0..<maxLength, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(hex: 0x94A3B8), lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(idx < entry.count ? AppColor.brandPrimary : Color.clear)
                    )
            }
        }
    }

    private var numpad: some View {
        VStack(spacing: 16) {
            ForEach(0..<3) { row in
                HStack(spacing: 24) {
                    ForEach(1...3, id: \.self) { col in
                        digitButton("\(row * 3 + col)")
                    }
                }
            }
            HStack(spacing: 24) {
                digitButton("").opacity(0).disabled(true)  // empty bottom-left
                digitButton("0")
                backspaceButton
            }
        }
    }

    private func digitButton(_ digit: String) -> some View {
        Button(action: { append(digit) }) {
            Text(digit)
                .font(.custom("Inter-Bold", size: 28))
                .foregroundStyle(Color(hex: 0x0F172A))
                .frame(width: 72, height: 72)
                .background(
                    Circle().fill(Color(hex: 0xF8FAFC))
                )
                .overlay(
                    Circle().stroke(Color(hex: 0xCBD5E1), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private var backspaceButton: some View {
        Button(action: backspace) {
            Image(systemName: "delete.left.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color(hex: 0x0F172A))
                .frame(width: 72, height: 72)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(entry.isEmpty)
        .opacity(entry.isEmpty ? 0.4 : 1)
    }

    private func append(_ digit: String) {
        guard digit.count == 1, "0123456789".contains(digit), entry.count < maxLength else { return }
        entry.append(digit)
        if entry.count == maxLength {
            onComplete(entry)
        }
    }

    private func backspace() {
        guard !entry.isEmpty else { return }
        entry.removeLast()
    }
}

#Preview {
    StatefulPreviewWrapper("") { binding in
        PasscodeKeypad(entry: binding)
            .padding()
    }
}

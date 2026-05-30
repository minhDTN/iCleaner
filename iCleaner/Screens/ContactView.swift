import SwiftUI
import MessageUI

// Figma `2005:23754` (Contact us). Header glass (white 80% + blur 12),
// "Get in touch" hero, 3 fields (Name / Email / Message), Send CTA #136DEC.
//
// MVP: Send opens MFMailComposeViewController to a stub support email. If mail
// isn't configured, fall back to an alert pointing to the support address.
struct ContactView: View {
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var message: String = ""
    @State private var showMail = false
    @State private var mailFallbackMessage: String?

    private static let supportEmail = "support@daliti-global.com"  // TODO: replace with real

    private var canSend: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        email.contains("@") &&
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.surfaceBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    headerText
                    formFields
                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .scrollIndicators(.hidden)

            sendButton
        }
        .navigationTitle("Contact Us")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMail) {
            MailComposer(
                recipients: [Self.supportEmail],
                subject: "iCleaner support — \(name)",
                body: "From: \(name) <\(email)>\n\n\(message)"
            )
        }
        .alert("Couldn't send", isPresented: Binding(
            get: { mailFallbackMessage != nil },
            set: { if !$0 { mailFallbackMessage = nil } }
        )) {
            Button("OK", role: .cancel) { mailFallbackMessage = nil }
        } message: { Text(mailFallbackMessage ?? "") }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Get in touch")
                .font(.custom("Inter-Bold", size: 24))
                .tracking(24 * -0.025)
                .foregroundStyle(Color(hex: 0x0F172A))
            Text("We'd love to hear from you. Send us a message and we'll respond as soon as possible.")
                .font(.custom("Inter-Regular", size: 14))
                .foregroundStyle(Color(hex: 0x64748B))
                .lineSpacing(20 - 14)
        }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 24) {
            field(label: "Name", placeholder: "Enter your name", text: $name)
            field(label: "Email Address", placeholder: "Enter your email address", text: $email, keyboard: .emailAddress)
            messageField
        }
    }

    private func field(label: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.custom("Inter-SemiBold", size: 14))
                .foregroundStyle(Color(hex: 0x0F172A))
            TextField(placeholder, text: text)
                .font(.custom("Inter-Regular", size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColor.surfaceBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: 0x136DEC).opacity(0.4), lineWidth: 1)
                )
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                .autocorrectionDisabled(keyboard == .emailAddress)
        }
    }

    private var messageField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Message")
                .font(.custom("Inter-SemiBold", size: 14))
                .foregroundStyle(Color(hex: 0x0F172A))
            TextEditor(text: $message)
                .font(.custom("Inter-Regular", size: 15))
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(AppColor.surfaceBackground)
                .frame(minHeight: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: 0x136DEC).opacity(0.4), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var sendButton: some View {
        Button(action: send) {
            Text("Send Message")
                .font(.custom("Inter-Bold", size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: 0x136DEC).opacity(canSend ? 1.0 : 0.4))
                        .shadow(color: Color(hex: 0x136DEC).opacity(canSend ? 0.2 : 0), radius: 6, x: 0, y: 4)
                        .shadow(color: Color(hex: 0x136DEC).opacity(canSend ? 0.2 : 0), radius: 15, x: 0, y: 10)
                )
        }
        .disabled(!canSend)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func send() {
        if MFMailComposeViewController.canSendMail() {
            showMail = true
        } else {
            mailFallbackMessage = "No mail account is configured. Please email us directly at \(Self.supportEmail)."
        }
    }
}

// MARK: - Mail compose bridge

private struct MailComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true)
        }
    }
}

#Preview {
    NavigationStack { ContactView() }
}

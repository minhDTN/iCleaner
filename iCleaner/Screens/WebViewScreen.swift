import SwiftUI
import WebKit

// In-app browser for Settings links (FAQ / Terms of Service / Privacy Policy).
// Pushed inside the Settings NavigationStack so the URL opens *in* the app
// (not Safari). Custom header avoids the iOS 26 toolbar glass pill; a thin top
// bar shows load progress.
struct WebViewScreen: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let url: URL
    @State private var isLoading = true
    @State private var progress: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .top) {
                WebView(url: url, isLoading: $isLoading, progress: $progress)
                if isLoading {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(AppColor.brandPrimary)
                }
            }
        }
        .background(AppColor.surfaceBackground)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0F172A))
                    .frame(width: 24, height: 24)
            }
            Spacer()
            Text(title)
                .font(.custom("Inter-Bold", size: 18))
                .foregroundStyle(Color(hex: 0x0F172A))
                .lineLimit(1)
            Spacer()
            Color.clear.frame(width: 24, height: 24)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xF1F5F9)).frame(height: 1) }
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var progress: Double

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.observe(webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView
        private var progressObs: NSKeyValueObservation?
        init(_ parent: WebView) { self.parent = parent }

        func observe(_ webView: WKWebView) {
            progressObs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in self?.parent.progress = wv.estimatedProgress }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in parent.isLoading = true }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in parent.isLoading = false }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in parent.isLoading = false }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in parent.isLoading = false }
        }
    }
}

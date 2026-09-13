import SwiftUI
import WebKit
import UIKit

struct ContentView: View {
    @StateObject private var discovery = BonjourDiscovery()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            TouchBarWebView(hostUrl: discovery.serverUrl)
                .edgesIgnoringSafeArea(.all)
        }
    }
}

struct TouchBarWebView: UIViewRepresentable {
    let hostUrl: String?
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "hapticFeedback")
        controller.add(context.coordinator, name: "macAction")
        config.userContentController = controller
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        
        loadInitialContent(webView: webView)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let hostUrl = hostUrl, let url = URL(string: hostUrl), uiView.url?.absoluteString != hostUrl {
            uiView.load(URLRequest(url: url))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    private func loadInitialContent(webView: WKWebView) {
        if let localUrl = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "WebResources") {
            webView.loadFileURL(localUrl, allowingReadAccessTo: localUrl.deletingLastPathComponent())
        } else if let hostUrl = hostUrl, let url = URL(string: hostUrl) {
            webView.load(URLRequest(url: url))
        } else {
            // Fallback para localhost (USB Tethering)
            if let defaultUrl = URL(string: "http://127.0.0.1:9876") {
                webView.load(URLRequest(url: defaultUrl))
            }
        }
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        private let impactLight = UIImpactFeedbackGenerator(style: .light)
        private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
        
        override init() {
            super.init()
            impactLight.prepare()
            impactMedium.prepare()
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "hapticFeedback" {
                if let type = message.body as? String, type == "medium" {
                    impactMedium.impactOccurred()
                } else {
                    impactLight.impactOccurred()
                }
            }
        }
    }
}

class BonjourDiscovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var serverUrl: String? = nil
    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    
    override init() {
        super.init()
        startDiscovery()
    }
    
    func startDiscovery() {
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_macdeck._tcp.", inDomain: "local.")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        if let host = sender.hostName {
            let cleanHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            DispatchQueue.main.async {
                self.serverUrl = "http://\(cleanHost):\(sender.port)"
            }
        }
    }
}

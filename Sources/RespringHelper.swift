import Foundation
import WebKit
import UIKit

enum RespringError: Error {
    case failed
}

enum RespringHelper {
    /// NeoSpring respring using WebKit GPU process
    /// Credit: @skadz108, @rooootdev, @neonmodder123
    @MainActor
    static func respring() throws {
        let webView = WKWebView(frame: .zero)
        webView.isHidden = true

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            throw RespringError.failed
        }
        window.addSubview(webView)

        // NeoSpring technique: load HTML that crashes GPU process
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body { margin: 0; padding: 0; overflow: hidden; }
                div {
                    width: 99999px;
                    height: 99999px;
                    background: radial-gradient(circle, red, blue);
                    animation: spin 0.0001s infinite linear;
                }
                @keyframes spin {
                    from { transform: rotate(0deg); }
                    to { transform: rotate(360deg); }
                }
            </style>
        </head>
        <body>
            <div></div>
            <div></div>
            <div></div>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }
}
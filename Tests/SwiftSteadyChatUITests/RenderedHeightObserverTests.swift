import Testing
import SwiftUI
import UIKit
@testable import SwiftSteadyChatUI

@MainActor
@Suite("RenderedHeightObserver")
struct RenderedHeightObserverTests {

    @Test("the observer reports the wrapped content's height once it lays out")
    func observerReportsHeight() {
        final class Sink {
            var heights: [CGFloat] = []
        }
        let sink = Sink()
        let host = UIHostingController(rootView: RenderedHeightObserver(
            content: Text("Hello").font(.body)
        ) { h in
            sink.heights.append(h)
        })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 100))
        window.rootViewController = host
        window.makeKeyAndVisible()
        _ = host.view
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        #expect(sink.heights.first != nil)
        #expect((sink.heights.first ?? 0) > 0)
    }
}

import SwiftUI
import SwiftSteadyChatUI

struct ContentView: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "bubble.left.and.bubble.right.fill")
        .font(.system(size: 56))
        .foregroundStyle(.tint)
      Text("Hello, SwiftSteadyChatUI")
        .font(.title)
      Text("v\(SwiftSteadyChatUI.version)")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding()
  }
}

#Preview {
  ContentView()
}

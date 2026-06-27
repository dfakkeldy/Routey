import SwiftUI

@main
struct RouteyMacProofApp: App {
  @State private var model = MacProofModel()

  var body: some Scene {
    WindowGroup("Routey Sync Proof") {
      MacProofView(model: model)
    }
    .defaultSize(width: 720, height: 520)
  }
}

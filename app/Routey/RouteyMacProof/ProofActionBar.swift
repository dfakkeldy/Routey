import SwiftUI

struct ProofActionBar: View {
  let model: MacProofModel

  var body: some View {
    HStack {
      Button("Refresh", systemImage: "arrow.clockwise") {
        Task { await model.refresh() }
      }
      .disabled(model.isWorking || !model.isOpen)

      Button("Seed", systemImage: "plus") {
        Task { await model.seedProofGraph() }
      }
      .disabled(model.isWorking || !model.isOpen)

      Button("Move", systemImage: "arrow.down") {
        Task { await model.moveFirstProofStop() }
      }
      .disabled(model.isWorking || !model.isOpen)

      Button("Delete", systemImage: "trash") {
        Task { await model.deleteProofData() }
      }
      .disabled(model.isWorking || !model.isOpen)

      Spacer()

      Button("Push", systemImage: "icloud.and.arrow.up") {
        Task { await model.pushChanges() }
      }
      .disabled(model.isWorking || !model.isOpen)

      Button("Pull", systemImage: "icloud.and.arrow.down") {
        Task { await model.pullChanges() }
      }
      .disabled(model.isWorking || !model.isOpen)

      Button("Sync", systemImage: "arrow.triangle.2.circlepath") {
        Task { await model.syncNow() }
      }
      .buttonStyle(.borderedProminent)
      .disabled(model.isWorking || !model.isOpen)
    }
  }
}

import SwiftUI

struct MacProofView: View {
  let model: MacProofModel

  var body: some View {
    VStack(alignment: .leading) {
      ProofStatusBar(status: model.status, isWorking: model.isWorking)
      Divider()
      ProofMetricGrid(counts: model.counts)
      Divider()
      ProofRouteList(routeNames: model.routeNames, proofStopOrder: model.proofStopOrder)
      Spacer()
      ProofActionBar(model: model)
    }
    .padding()
    .frame(minWidth: 640, minHeight: 420)
    .task {
      await model.start()
    }
  }
}

#Preview {
  MacProofView(model: MacProofModel())
}

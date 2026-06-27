import SwiftUI

struct ProofMetricGrid: View {
  let counts: ProofCounts

  var body: some View {
    Grid(alignment: .leadingFirstTextBaseline) {
      GridRow {
        ProofMetricCell(title: "Routes", value: counts.routes)
        ProofMetricCell(title: "Stops", value: counts.stops)
        ProofMetricCell(title: "Modules", value: counts.modules)
      }

      GridRow {
        ProofMetricCell(title: "Points", value: counts.deliveryPoints)
        ProofMetricCell(title: "Addresses", value: counts.addresses)
        ProofMetricCell(title: "Tags", value: counts.tags)
      }
    }
  }
}

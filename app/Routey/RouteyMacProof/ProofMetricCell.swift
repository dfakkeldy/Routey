import SwiftUI

struct ProofMetricCell: View {
  let title: String
  let value: Int

  var body: some View {
    VStack(alignment: .leading) {
      Text(title)
        .foregroundStyle(.secondary)
      Text(value, format: .number)
        .bold()
        .monospacedDigit()
    }
  }
}

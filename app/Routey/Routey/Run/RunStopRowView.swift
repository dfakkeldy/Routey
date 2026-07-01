import RouteyDomain
import SwiftUI

struct RunStopRowView: View {
  let stop: RunStopSummary

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: stop.isDone ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(stop.isDone ? .green : .secondary)

      VStack(alignment: .leading) {
        Text(stop.tieOut.isEmpty ? stop.displayName : stop.tieOut)
        if !stop.displayName.isEmpty && !stop.tieOut.isEmpty {
          Text(stop.displayName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      if stop.hasWarning {
        Image(systemName: "dog")
          .foregroundStyle(.orange)
      }

      if stop.parcelCount > 0 {
        Label("\(stop.parcelCount)", systemImage: "shippingbox.fill")
          .labelStyle(.titleAndIcon)
          .font(.caption)
      }
    }
    .opacity(stop.isDone ? 0.5 : 1)
  }
}

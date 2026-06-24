import SwiftUI
import RouteyModel

struct StopRowView: View {
  let stop: Stop

  var body: some View {
    VStack(alignment: .leading) {
      Text(stop.displayName.isEmpty ? "Untitled stop" : stop.displayName)
      if !stop.tieOut.isEmpty {
        Text(stop.tieOut)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

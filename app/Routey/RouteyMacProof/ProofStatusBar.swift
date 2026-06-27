import SwiftUI

struct ProofStatusBar: View {
  let status: String
  let isWorking: Bool

  var body: some View {
    HStack {
      if isWorking {
        ProgressView()
          .controlSize(.small)
      } else {
        Image(systemName: "checkmark.icloud")
          .foregroundStyle(.secondary)
      }

      Text(status)
        .lineLimit(2)
        .foregroundStyle(isWorking ? .primary : .secondary)
      Spacer()
    }
  }
}

import RouteyOCR
import SwiftUI

struct SnapResultView: View {
  let result: SnapMatchResult
  let model: SnapViewModel

  var body: some View {
    switch result.band {
    case .autoAccept(let id):
      ProgressView("Adding parcel…")
        .task { await model.accept(addressID: id) }
    case .review(let candidates):
      SnapPickList(
        title: "Which delivery point?",
        rawLines: result.readout.lines,
        candidates: candidates.map(\.candidate),
        model: model
      )
    case .noMatch:
      SnapPickList(
        title: "No confident match",
        rawLines: result.readout.lines,
        candidates: result.ranked.prefix(8).map(\.candidate),
        model: model,
        showsNotListed: true
      )
    }
  }
}

private struct SnapPickList: View {
  let title: String
  let rawLines: [String]
  let candidates: [AddressCandidate]
  let model: SnapViewModel
  var showsNotListed: Bool = false

  var body: some View {
    List {
      Section("Scanned label") {
        ForEach(Array(rawLines.enumerated()), id: \.offset) { _, line in
          Text(line).font(.callout).foregroundStyle(.secondary)
        }
      }
      Section(title) {
        ForEach(candidates) { candidate in
          Button {
            Task { await model.accept(addressID: candidate.id) }
          } label: {
            SnapCandidateRow(candidate: candidate)
          }
        }
        if showsNotListed {
          Button("Not listed — retake", systemImage: "arrow.uturn.backward") {
            model.reset()
          }
        }
      }
    }
  }
}

private struct SnapCandidateRow: View {
  let candidate: AddressCandidate

  var body: some View {
    VStack(alignment: .leading) {
      Text(candidate.civicNumber.map { "\($0) \(candidate.street)" } ?? candidate.street)
        .bold()
      if let occupant = candidate.occupantName {
        Text(occupant).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

import RouteyDomain
import RouteyModel
import SQLiteData
import SwiftUI

private struct RunStopDetailRequest: FetchKeyRequest {
  let runID: TodaysRun.ID
  let runStopID: RunStop.ID

  func fetch(_ db: Database) throws -> RunStopDetail {
    try RunStopDetail.load(runStopID: runStopID, runID: runID, db)
  }
}

struct RunStopDetailView: View {
  @Fetch private var detail: RunStopDetail

  init(runID: TodaysRun.ID, runStopID: RunStop.ID) {
    _detail = Fetch(
      wrappedValue: .empty,
      RunStopDetailRequest(runID: runID, runStopID: runStopID)
    )
  }

  var body: some View {
    Form {
      if !detail.warningTags.isEmpty {
        Section("Warnings") {
          ForEach(detail.warningTags, id: \.self) { tag in
            Label(tag, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
          }
        }
      }

      Section("Addresses") {
        if detail.addresses.isEmpty {
          Text("No addresses")
            .foregroundStyle(.secondary)
        } else {
          ForEach(detail.addresses) { address in
            VStack(alignment: .leading) {
              Text(addressTitle(address))
              if let occupant = address.occupant, !occupant.isEmpty {
                Text(occupant)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }

      Section("Parcels") {
        if detail.parcels.isEmpty {
          Text("No parcels")
            .foregroundStyle(.secondary)
        } else {
          ForEach(detail.parcels) { parcel in
            VStack(alignment: .leading) {
              Text(parcel.labelSnapshot.isEmpty ? "Parcel" : parcel.labelSnapshot)

              if !parcel.trackingCode.isEmpty {
                Text(parcel.trackingCode)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              HStack {
                if parcel.requiresSignature {
                  Label("Signature", systemImage: "signature")
                }

                if parcel.isCustoms {
                  Label("Customs", systemImage: "globe")
                }

                if parcel.isDelivered {
                  Label("Delivered", systemImage: "checkmark.circle")
                }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle("Stop Detail")
  }

  private func addressTitle(_ address: RunStopDetail.AddressLine) -> String {
    [address.civic, address.street]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}

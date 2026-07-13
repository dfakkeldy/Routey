import SQLiteData
import SwiftUI
import RouteyDomain
import RouteyModel

struct StopDetailView: View {
  let stop: Stop
  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.defaultSyncEngine) private var syncEngine
  @FetchAll private var deliveryPoints: [DeliveryPoint]
  @State private var displayName: String
  @State private var tieOut: String
  @State private var savedDisplayName: String
  @State private var savedTieOut: String
  @State private var errorMessage = ""
  @State private var isShowingError = false

  init(stop: Stop) {
    self.stop = stop
    _deliveryPoints = FetchAll(
      DeliveryPoint
        .where { $0.stopID.eq(#bind(stop.id)) }
        .order { $0.label }
    )
    _displayName = State(initialValue: stop.displayName)
    _tieOut = State(initialValue: stop.tieOut)
    _savedDisplayName = State(initialValue: stop.displayName)
    _savedTieOut = State(initialValue: stop.tieOut)
  }

  var body: some View {
    Form {
      Section("Stop") {
        TextField("Display name", text: $displayName)
        TextField("Tie-out", text: $tieOut)
      }

      Section("Delivery Points") {
        if deliveryPoints.isEmpty {
          Text("No delivery points")
            .foregroundStyle(.secondary)
        } else {
          ForEach(deliveryPoints) { deliveryPoint in
            DeliveryPointRowView(deliveryPoint: deliveryPoint)
          }
        }
      }
    }
    .navigationTitle(displayName.isEmpty ? "Stop" : displayName)
    .navigationDestination(for: Address.self) { address in
      AddressEditorView(address: address)
    }
    .toolbar {
      Button("Save", systemImage: "checkmark", action: save)
        .disabled(!hasChanges)
    }
    .alert("Couldn't Save Stop", isPresented: $isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private var hasChanges: Bool {
    displayName != savedDisplayName || tieOut != savedTieOut
  }

  private func save() {
    do {
      try RouteEditing.updateStopDisplayName(stop.id, to: displayName, in: database)
      try RouteEditing.updateStopTieOut(stop.id, to: tieOut, in: database)
      savedDisplayName = displayName
      savedTieOut = tieOut
      sendChanges(reason: "stop saved")
    } catch {
      show(error)
    }
  }

  private func sendChanges(reason: String) {
    Task {
      await RouteySyncing.sendChanges(reason: reason, using: syncEngine)
    }
  }

  private func show(_ error: any Error) {
    errorMessage = error.localizedDescription
    isShowingError = true
  }
}

private struct DeliveryPointRowView: View {
  let deliveryPoint: DeliveryPoint
  @FetchAll private var addresses: [Address]

  init(deliveryPoint: DeliveryPoint) {
    self.deliveryPoint = deliveryPoint
    _addresses = FetchAll(
      Address
        .where { address in
          DeliveryPointAddress
            .where {
              $0.deliveryPointID.eq(#bind(deliveryPoint.id))
                && $0.addressID.eq(address.id)
            }
            .exists()
        }
        .order { $0.street }
    )
  }

  var body: some View {
    DisclosureGroup(title) {
      if addresses.isEmpty {
        Text("No addresses")
          .foregroundStyle(.secondary)
      } else {
        ForEach(addresses) { address in
          NavigationLink(value: address) {
            Text(title(for: address))
          }
        }
      }
    }
  }

  private var title: String {
    if !deliveryPoint.label.isEmpty {
      deliveryPoint.label
    } else {
      deliveryPoint.kind
    }
  }

  private func title(for address: Address) -> String {
    [
      address.civicNumber.map { $0.formatted(.number.grouping(.never)) },
      address.street.isEmpty ? nil : address.street,
      address.occupantName,
    ]
    .compactMap(\.self)
    .joined(separator: " ")
  }
}

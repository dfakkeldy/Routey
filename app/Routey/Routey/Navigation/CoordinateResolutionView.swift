import SQLiteData
import SwiftUI
import RouteyDomain
import RouteyModel

struct CoordinateResolutionView: View {
  let routeID: Route.ID

  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.defaultSyncEngine) private var syncEngine
  @State private var isResolving = false
  @State private var statusMessage: String?
  @State private var failureMessage: String?

  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Button("Resolve Coordinates", systemImage: "mappin.and.ellipse", action: resolveCoordinates)
          .disabled(isResolving)

        Spacer()

        if isResolving {
          ProgressView()
        }
      }

      if let statusMessage {
        Text(statusMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let failureMessage {
        Text(failureMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }

  private func resolveCoordinates() {
    guard !isResolving else { return }

    isResolving = true
    statusMessage = nil
    failureMessage = nil

    Task {
      do {
        let startingCount = try CoordinateResolution.candidates(routeID: routeID, in: database).count
        let resolvedCount = try await AppleAddressGeocoder.service()
          .resolveMissingCoordinates(routeID: routeID, in: database)
        let remainingCount = try CoordinateResolution.candidates(routeID: routeID, in: database).count

        if resolvedCount > 0 {
          await RouteySyncing.sendChanges(reason: "coordinates resolved", using: syncEngine)
        }

        await MainActor.run {
          isResolving = false
          statusMessage = status(
            startingCount: startingCount,
            resolvedCount: resolvedCount,
            remainingCount: remainingCount
          )
        }
      } catch {
        await MainActor.run {
          isResolving = false
          failureMessage = "Try again when online"
        }
      }
    }
  }

  private func status(startingCount: Int, resolvedCount: Int, remainingCount: Int) -> String {
    if startingCount == 0 {
      return "All coordinates resolved"
    }

    if remainingCount > 0 {
      if resolvedCount > 0 {
        let label = resolvedCount == 1 ? "address" : "addresses"
        return "Resolved \(resolvedCount.formatted(.number)) \(label); \(remainingCount.formatted(.number)) could not be located"
      }
      return "Some addresses could not be located"
    }

    let label = resolvedCount == 1 ? "address" : "addresses"
    return "Resolved \(resolvedCount.formatted(.number)) \(label)"
  }
}

import Foundation
import SQLiteData
import RouteyModel
import RouteyNavigation

public struct RunOptimizationSuggestion: Equatable, Sendable {
  public var orderedRunStopIDs: [RunStop.ID]
  public var unresolvedRunStopIDs: [RunStop.ID]
  public var totalDistance: Double

  public init(
    orderedRunStopIDs: [RunStop.ID],
    unresolvedRunStopIDs: [RunStop.ID],
    totalDistance: Double
  ) {
    self.orderedRunStopIDs = orderedRunStopIDs
    self.unresolvedRunStopIDs = unresolvedRunStopIDs
    self.totalDistance = totalDistance
  }
}

public enum RunOptimization {
  public static func suggest(
    runID: TodaysRun.ID,
    start: NavigationCoordinate?,
    in database: any DatabaseReader
  ) throws -> RunOptimizationSuggestion {
    try database.read { db in
      try suggest(runID: runID, start: start, in: db)
    }
  }

  public static func apply(
    _ suggestion: RunOptimizationSuggestion,
    to runID: TodaysRun.ID,
    in database: any DatabaseWriter
  ) throws {
    try database.write { db in
      let runStops = try RunStop
        .where { $0.runID.eq(#bind(runID)) }
        .order { $0.sortIndex }
        .fetchAll(db)
      let runStopIDs = Set(runStops.map(\.id))
      let optimizedIDs = suggestion.orderedRunStopIDs.filter { runStopIDs.contains($0) }
      guard !optimizedIDs.isEmpty else { return }

      let optimizedIDSet = Set(optimizedIDs)
      let remainingIDs = runStops
        .filter { !optimizedIDSet.contains($0.id) }
        .map(\.id)

      for (index, runStopID) in (optimizedIDs + remainingIDs).enumerated() {
        try RunStop.find(runStopID)
          .update { $0.sortIndex = #bind(Double(index)) }
          .execute(db)
      }
    }
  }

  private static func suggest(
    runID: TodaysRun.ID,
    start: NavigationCoordinate?,
    in db: Database
  ) throws -> RunOptimizationSuggestion {
    let runStops = try RunStop
      .where { $0.runID.eq(#bind(runID)) }
      .order { $0.sortIndex }
      .fetchAll(db)
    let parcelStopIDs = try parcelStopIDs(runID: runID, in: db)
    let stopIDs = Set(runStops.compactMap(\.stopID))
    let stopsByID = Dictionary(
      uniqueKeysWithValues: try Stop.all.fetchAll(db)
        .filter { stopIDs.contains($0.id) }
        .map { ($0.id, $0) }
    )

    var candidates: [RouteStopCandidate] = []
    var unresolvedRunStopIDs: [RunStop.ID] = []

    for runStop in runStops {
      guard let stopID = runStop.stopID, parcelStopIDs.contains(stopID) else { continue }
      guard
        let stop = stopsByID[stopID],
        let latitude = stop.latitude,
        let longitude = stop.longitude
      else {
        unresolvedRunStopIDs.append(runStop.id)
        continue
      }

      candidates.append(
        RouteStopCandidate(
          id: runStop.id,
          label: runStop.displayName,
          coordinate: NavigationCoordinate(latitude: latitude, longitude: longitude),
          existingSortIndex: runStop.sortIndex
        )
      )
    }

    let result = RouteOptimizer.optimize(start: start, stops: candidates)
    return RunOptimizationSuggestion(
      orderedRunStopIDs: result.orderedStops.map(\.candidate.id),
      unresolvedRunStopIDs: unresolvedRunStopIDs,
      totalDistance: result.totalDistance
    )
  }

  private static func parcelStopIDs(
    runID: TodaysRun.ID,
    in db: Database
  ) throws -> Set<Stop.ID> {
    let parcels = try Parcel
      .where { $0.runID.eq(#bind(runID)) }
      .fetchAll(db)
    let parcelAddressIDs = Set(parcels.compactMap(\.addressID))
    guard !parcelAddressIDs.isEmpty else { return [] }

    let links = try DeliveryPointAddress.all.fetchAll(db)
      .filter { parcelAddressIDs.contains($0.addressID) }
    let deliveryPointIDs = Set(links.map(\.deliveryPointID))
    guard !deliveryPointIDs.isEmpty else { return [] }

    return Set(
      try DeliveryPoint.all.fetchAll(db)
        .filter { deliveryPointIDs.contains($0.id) }
        .map(\.stopID)
    )
  }
}

import CoreLocation
import Foundation
import RouteyDomain
import RouteyModel
import SQLiteData

struct RunMapStop: Identifiable, Equatable {
  var id: UUID
  var title: String
  var subtitle: String
  var order: Int
  var coordinate: CLLocationCoordinate2D

  static func == (lhs: RunMapStop, rhs: RunMapStop) -> Bool {
    lhs.id == rhs.id
      && lhs.title == rhs.title
      && lhs.subtitle == rhs.subtitle
      && lhs.order == rhs.order
      && lhs.coordinate.latitude == rhs.coordinate.latitude
      && lhs.coordinate.longitude == rhs.coordinate.longitude
  }
}

struct RunMapSnapshot: Equatable {
  var stops: [RunMapStop]
  var unresolvedCount: Int
  var totalDistance: Double

  static let empty = RunMapSnapshot(stops: [], unresolvedCount: 0, totalDistance: 0)

  static func load(runID: TodaysRun.ID, in database: any DatabaseReader) throws -> RunMapSnapshot {
    let suggestion = try RunOptimization.suggest(runID: runID, start: nil, in: database)
    return try database.read { db in
      let runStops = try RunStop
        .where { $0.runID.eq(#bind(runID)) }
        .order { $0.sortIndex }
        .fetchAll(db)
      let stopIDs = Set(runStops.compactMap(\.stopID))
      let stopsByID = Dictionary(
        uniqueKeysWithValues: try Stop.all.fetchAll(db)
          .filter { stopIDs.contains($0.id) }
          .map { ($0.id, $0) }
      )

      return make(suggestion: suggestion, runStops: runStops, stopsByID: stopsByID)
    }
  }

  static func make(
    suggestion: RunOptimizationSuggestion,
    runStops: [RunStop],
    stopsByID: [Stop.ID: Stop]
  ) -> RunMapSnapshot {
    let runStopsByID = Dictionary(uniqueKeysWithValues: runStops.map { ($0.id, $0) })
    let mapStops = suggestion.orderedRunStopIDs.enumerated().compactMap { offset, runStopID -> RunMapStop? in
      guard
        let runStop = runStopsByID[runStopID],
        let stopID = runStop.stopID,
        let stop = stopsByID[stopID],
        let latitude = stop.latitude,
        let longitude = stop.longitude
      else {
        return nil
      }

      return RunMapStop(
        id: runStop.id,
        title: runStop.displayName.isEmpty ? "Stop \(offset + 1)" : runStop.displayName,
        subtitle: subtitle(for: runStop),
        order: offset + 1,
        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
      )
    }

    return RunMapSnapshot(
      stops: mapStops,
      unresolvedCount: suggestion.unresolvedRunStopIDs.count,
      totalDistance: suggestion.totalDistance
    )
  }

  private static func subtitle(for runStop: RunStop) -> String {
    [runStop.tieOut, runStop.kind]
      .filter { !$0.isEmpty }
      .joined(separator: " - ")
  }
}

import Foundation
import SQLiteData
import RouteyImport
import RouteyModel
import RouteySearch

public enum RouteImporter {
  public static func importRoute(
    named name: String,
    from result: ParseResult,
    into database: any DatabaseWriter
  ) throws -> ImportSummary {
    let routeID = UUID()

    try database.write { db in
      try Route.insert {
        Route(id: routeID, name: name)
      }
      .execute(db)

      for (index, parsedStop) in result.stops.enumerated() {
        let stopID = UUID()
        let deliveryPointID = UUID()
        let addressID = UUID()
        let displayName = displayName(for: parsedStop)

        try Stop.insert {
          Stop(
            id: stopID,
            routeID: routeID,
            tieOut: parsedStop.tieOut ?? "",
            sortIndex: Double(index),
            kind: "pointOfCall",
            displayName: displayName,
            notes: parsedStop.notes ?? ""
          )
        }
        .execute(db)

        try DeliveryPoint.insert {
          DeliveryPoint(
            id: deliveryPointID,
            stopID: stopID,
            kind: "roadsideBox",
            label: displayName
          )
        }
        .execute(db)

        try Address.insert {
          Address(
            id: addressID,
            civicNumber: parsedStop.civicNumber,
            street: parsedStop.street,
            occupantName: parsedStop.occupantName,
            notes: parsedStop.notes ?? ""
          )
        }
        .execute(db)

        try DeliveryPointAddress.insert {
          DeliveryPointAddress(deliveryPointID: deliveryPointID, addressID: addressID)
        }
        .execute(db)
      }

      try SearchIndex.install(db)
      try SearchIndex.rebuild(from: db)
    }

    return ImportSummary(routeID: routeID, stopsCreated: result.stops.count, skipped: result.skipped)
  }

  public static func displayName(for stop: ParsedStop) -> String {
    [
      stop.civicNumber.map(String.init),
      stop.street.isEmpty ? nil : stop.street,
    ]
    .compactMap(\.self)
    .joined(separator: " ")
  }
}

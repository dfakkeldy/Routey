import Foundation
import RouteyModel
import SQLiteData

public struct TemporaryParcelInput: Equatable, Sendable {
  public var serviceDate: String
  public var labelSnapshot: String
  public var civicNumber: Int?
  public var street: String
  public var postalCode: String?
  public var trackingCode: String
  public var trackingSymbology: String
  public var requiresSignature: Bool
  public var isCustoms: Bool
  public var toDoor: Bool

  public init(
    serviceDate: String,
    labelSnapshot: String,
    civicNumber: Int?,
    street: String,
    postalCode: String?,
    trackingCode: String,
    trackingSymbology: String,
    requiresSignature: Bool,
    isCustoms: Bool,
    toDoor: Bool
  ) {
    self.serviceDate = serviceDate
    self.labelSnapshot = labelSnapshot
    self.civicNumber = civicNumber
    self.street = street
    self.postalCode = postalCode
    self.trackingCode = trackingCode
    self.trackingSymbology = trackingSymbology
    self.requiresSignature = requiresSignature
    self.isCustoms = isCustoms
    self.toDoor = toDoor
  }
}

public struct TemporaryRouteBuildResult: Equatable, Sendable {
  public var runID: TodaysRun.ID
  public var parcelID: Parcel.ID

  public init(runID: TodaysRun.ID, parcelID: Parcel.ID) {
    self.runID = runID
    self.parcelID = parcelID
  }
}

public enum TemporaryRouteBuilder {
  public static let routeName = "Parcel Pile"

  @discardableResult
  public static func addParcelToTemporaryRoute(
    _ input: TemporaryParcelInput,
    into database: any DatabaseWriter
  ) throws -> TodaysRun.ID {
    try addParcelToTemporaryRouteWithResult(input, into: database).runID
  }

  public static func addParcelToTemporaryRouteWithResult(
    _ input: TemporaryParcelInput,
    into database: any DatabaseWriter
  ) throws -> TemporaryRouteBuildResult {
    try database.write { db in
      let route = try temporaryRoute(in: db)
      let run = try todaysRun(routeID: route.id, serviceDate: input.serviceDate, in: db)
      let sortIndex = try nextSortIndex(routeID: route.id, in: db)
      let displayName = displayName(for: input)
      let stopID = UUID()
      let addressID = UUID()
      let deliveryPointID = UUID()
      let parcelID = UUID()

      try Stop.insert {
        Stop(
          id: stopID,
          routeID: route.id,
          sortIndex: sortIndex,
          kind: input.toDoor ? "doorVisit" : "pointOfCall",
          displayName: displayName
        )
      }
      .execute(db)

      try Address.insert {
        Address(
          id: addressID,
          civicNumber: input.civicNumber,
          street: input.street,
          postalCode: input.postalCode
        )
      }
      .execute(db)

      try DeliveryPoint.insert {
        DeliveryPoint(id: deliveryPointID, stopID: stopID, label: displayName)
      }
      .execute(db)

      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: deliveryPointID, addressID: addressID)
      }
      .execute(db)

      try RunStop.insert {
        RunStop(
          runID: run.id,
          stopID: stopID,
          displayName: displayName,
          kind: input.toDoor ? "doorVisit" : "pointOfCall",
          sortIndex: sortIndex
        )
      }
      .execute(db)

      try Parcel.insert {
        Parcel(
          id: parcelID,
          runID: run.id,
          addressID: addressID,
          source: "ocr",
          toDoor: input.toDoor,
          requiresSignature: input.requiresSignature,
          isCustoms: input.isCustoms,
          labelSnapshot: input.labelSnapshot,
          trackingCode: input.trackingCode,
          trackingSymbology: input.trackingSymbology
        )
      }
      .execute(db)

      return TemporaryRouteBuildResult(runID: run.id, parcelID: parcelID)
    }
  }

  private static func temporaryRoute(in db: Database) throws -> Route {
    if let route = try Route.all.fetchAll(db).first(where: { $0.name == routeName }) {
      return route
    }

    let route = Route(name: routeName)
    try Route.insert { route }.execute(db)
    return route
  }

  private static func todaysRun(
    routeID: Route.ID,
    serviceDate: String,
    in db: Database
  ) throws -> TodaysRun {
    if let run = try TodaysRun.all.fetchAll(db).first(where: {
      $0.routeID == routeID && $0.serviceDate == serviceDate
    }) {
      return run
    }

    let run = TodaysRun(routeID: routeID, serviceDate: serviceDate, createdAt: .now)
    try TodaysRun.insert { run }.execute(db)
    return run
  }

  private static func nextSortIndex(routeID: Route.ID, in db: Database) throws -> Double {
    let lastStop = try Stop
      .where { $0.routeID.eq(#bind(routeID)) }
      .order { $0.sortIndex }
      .fetchAll(db)
      .last

    return (lastStop?.sortIndex ?? -1) + 1
  }

  private static func displayName(for input: TemporaryParcelInput) -> String {
    var parts: [String] = []
    if let civicNumber = input.civicNumber {
      parts.append(civicNumber.formatted(.number.grouping(.never)))
    }
    if !input.street.isEmpty {
      parts.append(input.street)
    }

    let title = parts.joined(separator: " ")
    return title.isEmpty ? "Parcel stop" : title
  }
}

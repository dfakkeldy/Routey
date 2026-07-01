import Foundation
import RouteyModel
import SQLiteData

public struct RunStopSummary: Equatable, Identifiable, Sendable {
  public var runStopID: UUID
  public var stopID: UUID?
  public var tieOut: String
  public var displayName: String
  public var kind: String
  public var isDone: Bool
  public var sortIndex: Double
  public var hasWarning: Bool
  public var parcelCount: Int

  public var id: UUID { runStopID }

  public init(
    runStopID: UUID,
    stopID: UUID?,
    tieOut: String,
    displayName: String,
    kind: String,
    isDone: Bool,
    sortIndex: Double,
    hasWarning: Bool,
    parcelCount: Int
  ) {
    self.runStopID = runStopID
    self.stopID = stopID
    self.tieOut = tieOut
    self.displayName = displayName
    self.kind = kind
    self.isDone = isDone
    self.sortIndex = sortIndex
    self.hasWarning = hasWarning
    self.parcelCount = parcelCount
  }
}

public struct RunBoard: Equatable, Sendable {
  public var total: Int
  public var doneCount: Int
  public var signatureCount: Int
  public var stops: [RunStopSummary]

  public init(
    total: Int = 0,
    doneCount: Int = 0,
    signatureCount: Int = 0,
    stops: [RunStopSummary] = []
  ) {
    self.total = total
    self.doneCount = doneCount
    self.signatureCount = signatureCount
    self.stops = stops
  }

  public static let empty = RunBoard()

  public static func load(runID: TodaysRun.ID, _ db: Database) throws -> RunBoard {
    let runStops = try RunStop
      .where { $0.runID.eq(#bind(runID)) }
      .order { $0.sortIndex }
      .fetchAll(db)
    let parcels = try Parcel
      .where { $0.runID.eq(#bind(runID)) }
      .fetchAll(db)

    let stopIDs = Set(runStops.compactMap(\.stopID))
    let deliveryPoints = try DeliveryPoint.all.fetchAll(db).filter { stopIDs.contains($0.stopID) }
    let pointStopByID = Dictionary(uniqueKeysWithValues: deliveryPoints.map { ($0.id, $0.stopID) })
    let pointIDs = Set(deliveryPoints.map(\.id))
    let links = try DeliveryPointAddress.all.fetchAll(db).filter { pointIDs.contains($0.deliveryPointID) }
    let addressIDs = Set(links.map(\.addressID))
    let addressTags = try AddressTag.all.fetchAll(db).filter { addressIDs.contains($0.addressID) }
    let warningTagIDs = Set(try Tag.all.fetchAll(db).filter(\.isWarning).map(\.id))
    let warnedAddressIDs = Set(addressTags.filter { warningTagIDs.contains($0.tagID) }.map(\.addressID))

    var addressIDsByStop: [UUID: Set<UUID>] = [:]
    var stopIDsByAddress: [UUID: Set<UUID>] = [:]
    for link in links {
      guard let stopID = pointStopByID[link.deliveryPointID] else { continue }
      addressIDsByStop[stopID, default: []].insert(link.addressID)
      stopIDsByAddress[link.addressID, default: []].insert(stopID)
    }

    var parcelCountByStop: [UUID: Int] = [:]
    for parcel in parcels {
      guard let addressID = parcel.addressID, let stopIDs = stopIDsByAddress[addressID] else { continue }
      for stopID in stopIDs {
        parcelCountByStop[stopID, default: 0] += 1
      }
    }

    let summaries = runStops.map { runStop in
      let stopAddressIDs = runStop.stopID.flatMap { addressIDsByStop[$0] } ?? []

      return RunStopSummary(
        runStopID: runStop.id,
        stopID: runStop.stopID,
        tieOut: runStop.tieOut,
        displayName: runStop.displayName,
        kind: runStop.kind,
        isDone: runStop.isDone,
        sortIndex: runStop.sortIndex,
        hasWarning: !stopAddressIDs.isDisjoint(with: warnedAddressIDs),
        parcelCount: runStop.stopID.flatMap { parcelCountByStop[$0] } ?? 0
      )
    }

    return RunBoard(
      total: runStops.count,
      doneCount: runStops.filter(\.isDone).count,
      signatureCount: parcels.filter { $0.requiresSignature && !$0.isDelivered }.count,
      stops: summaries
    )
  }
}

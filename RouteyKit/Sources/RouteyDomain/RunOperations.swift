import Foundation
import SQLiteData
import RouteyModel

public enum RunOperations {
  public enum ValidationError: Equatable, Error {
    case runStopNotFound(RunStop.ID)
    case runStopDoesNotBelongToRun(runStopID: RunStop.ID, runID: TodaysRun.ID)
    case parcelNotFound(Parcel.ID)
    case parcelDoesNotBelongToRun(parcelID: Parcel.ID, runID: TodaysRun.ID)
  }

  private struct FollowUpTarget {
    var stopID: Stop.ID
    var text: String
  }

  private static let terminalParcelOutcomes: Set<String> = [
    "delivered", "safedrop", "mailbox", "inPerson", "leftAtDoor",
  ]

  public static func moveRunStop(
    _ id: RunStop.ID,
    after precedingRunStopID: RunStop.ID?,
    in database: any DatabaseWriter
  ) throws {
    guard precedingRunStopID != id else { return }

    try database.write { db in
      guard let runStop = try RunStop.find(id).fetchOne(db) else { return }
      let siblings = try RunStop
        .where { $0.runID.eq(#bind(runStop.runID)) }
        .order { $0.sortIndex }
        .fetchAll(db)
        .filter { $0.id != id }
      let sortIndex = sortIndex(for: siblings, after: precedingRunStopID)

      try RunStop.find(id)
        .update { $0.sortIndex = #bind(sortIndex) }
        .execute(db)
    }
  }

  @discardableResult
  public static func addParcel(
    runID: TodaysRun.ID,
    addressID: Address.ID?,
    source: String,
    sizeClass: String = "",
    requiresSignature: Bool,
    isCustoms: Bool,
    toDoor: Bool,
    labelSnapshot: String,
    trackingCode: String,
    trackingSymbology: String,
    in database: any DatabaseWriter
  ) throws -> Parcel.ID {
    let parcelID = UUID()

    try database.write { db in
      try Parcel.insert {
        Parcel(
          id: parcelID,
          runID: runID,
          addressID: addressID,
          source: source,
          sizeClass: sizeClass,
          toDoor: toDoor,
          requiresSignature: requiresSignature,
          isCustoms: isCustoms,
          isDelivered: false,
          labelSnapshot: labelSnapshot,
          trackingCode: trackingCode,
          trackingSymbology: trackingSymbology
        )
      }
      .execute(db)
    }

    return parcelID
  }

  public static func removeParcel(_ id: Parcel.ID, in database: any DatabaseWriter) throws {
    try database.write { db in
      try Parcel.find(id).delete().execute(db)
    }
  }

  public static func signatureCount(
    runID: TodaysRun.ID,
    in database: any DatabaseReader
  ) throws -> Int {
    try database.read { db in
      try Parcel
        .where { $0.runID.eq(#bind(runID)) }
        .fetchAll(db)
        .filter { $0.requiresSignature && !$0.isDelivered }
        .count
    }
  }

  @discardableResult
  public static func logDelivery(
    runID: TodaysRun.ID,
    runStopID: RunStop.ID,
    parcelID: Parcel.ID?,
    addressID: Address.ID?,
    outcome: String,
    location: (lat: Double, lon: Double)?,
    photoPath: String?,
    loggedAt: Date,
    in database: any DatabaseWriter
  ) throws -> DeliveryRecord.ID {
    let recordID = UUID()

    try database.write { db in
      guard let runStop = try RunStop.find(runStopID).fetchOne(db) else {
        throw ValidationError.runStopNotFound(runStopID)
      }
      guard runStop.runID == runID else {
        throw ValidationError.runStopDoesNotBelongToRun(runStopID: runStopID, runID: runID)
      }

      if let parcelID {
        guard let parcel = try Parcel.find(parcelID).fetchOne(db) else {
          throw ValidationError.parcelNotFound(parcelID)
        }
        guard parcel.runID == runID else {
          throw ValidationError.parcelDoesNotBelongToRun(parcelID: parcelID, runID: runID)
        }
      }

      try DeliveryRecord.insert {
        DeliveryRecord(
          id: recordID,
          runID: runID,
          addressID: addressID,
          parcelID: parcelID,
          outcome: outcome,
          latitude: location?.lat,
          longitude: location?.lon,
          loggedAt: loggedAt,
          photoPath: photoPath
        )
      }
      .execute(db)

      if let parcelID, terminalParcelOutcomes.contains(outcome) {
        try Parcel.find(parcelID)
          .update { $0.isDelivered = #bind(true) }
          .execute(db)
      }

      if outcome == "notHomeCarded", let addressID,
        let target = try compartmentFollowUpTarget(for: addressID, in: db)
      {
        try insertFollowUpTask(
          runID: runID,
          targetStopID: target.stopID,
          addressID: addressID,
          text: target.text,
          in: db
        )
      }
    }

    return recordID
  }

  @discardableResult
  public static func createFollowUpTask(
    runID: TodaysRun.ID,
    targetStopID: Stop.ID?,
    addressID: Address.ID?,
    text: String,
    in database: any DatabaseWriter
  ) throws -> FollowUpTask.ID {
    let taskID = UUID()

    try database.write { db in
      try insertFollowUpTask(
        id: taskID,
        runID: runID,
        targetStopID: targetStopID,
        addressID: addressID,
        text: text,
        in: db
      )
    }

    return taskID
  }

  public static func bulkCheckOff(
    throughRunStop id: RunStop.ID,
    runID: TodaysRun.ID,
    in database: any DatabaseWriter
  ) throws {
    try database.write { db in
      guard let target = try RunStop.find(id).fetchOne(db), target.runID == runID else { return }
      let runStops = try RunStop
        .where { $0.runID.eq(#bind(runID)) }
        .fetchAll(db)

      for runStop in runStops where runStop.sortIndex <= target.sortIndex {
        try RunStop.find(runStop.id)
          .update { $0.isDone = #bind(true) }
          .execute(db)
      }
    }
  }

  public static func setRunStopDone(
    _ id: RunStop.ID,
    done: Bool,
    in database: any DatabaseWriter
  ) throws {
    try database.write { db in
      try RunStop.find(id)
        .update { $0.isDone = #bind(done) }
        .execute(db)
    }
  }

  private static func sortIndex(for siblings: [RunStop], after precedingRunStopID: RunStop.ID?) -> Double {
    guard let precedingRunStopID else {
      return (siblings.first?.sortIndex ?? 1.0) - 1.0
    }

    guard
      let precedingIndex = siblings.firstIndex(where: { $0.id == precedingRunStopID })
    else {
      return (siblings.last?.sortIndex ?? -1.0) + 1.0
    }

    let lowerBound = siblings[precedingIndex].sortIndex
    guard precedingIndex + 1 < siblings.count else {
      return lowerBound + 1.0
    }

    let upperBound = siblings[precedingIndex + 1].sortIndex
    return (lowerBound + upperBound) / 2.0
  }

  private static func compartmentFollowUpTarget(
    for addressID: Address.ID,
    in db: Database
  ) throws -> FollowUpTarget? {
    let links = try DeliveryPointAddress
      .where { $0.addressID.eq(#bind(addressID)) }
      .fetchAll(db)
    let deliveryPoints = try DeliveryPoint.all.fetchAll(db)
    let modules = try Module.all.fetchAll(db)

    for link in links {
      guard
        let deliveryPoint = deliveryPoints.first(where: { $0.id == link.deliveryPointID }),
        deliveryPoint.kind == "compartment"
      else {
        continue
      }

      let moduleName = deliveryPoint.moduleID.flatMap { moduleID in
        modules.first(where: { $0.id == moduleID })?.name
      } ?? ""
      let locationText = [moduleName, deliveryPoint.label]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
      let taskText = locationText.isEmpty
        ? "drop notice card"
        : "drop notice card in \(locationText)"

      return FollowUpTarget(stopID: deliveryPoint.stopID, text: taskText)
    }

    return nil
  }

  private static func insertFollowUpTask(
    id: FollowUpTask.ID = UUID(),
    runID: TodaysRun.ID,
    targetStopID: Stop.ID?,
    addressID: Address.ID?,
    text: String,
    in db: Database
  ) throws {
    try FollowUpTask.insert {
      FollowUpTask(
        id: id,
        runID: runID,
        targetStopID: targetStopID,
        addressID: addressID,
        text: text,
        isDone: false
      )
    }
    .execute(db)
  }
}

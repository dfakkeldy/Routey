import Foundation
import SQLiteData
import RouteyModel
import RouteySearch

public enum RouteEditing {
  @discardableResult
  public static func addStop(
    routeID: Route.ID,
    tieOut: String,
    displayName: String,
    after precedingStopID: Stop.ID?,
    into database: any DatabaseWriter
  ) throws -> Stop.ID {
    let stopID = UUID()

    try database.write { db in
      let siblings = try Stop
        .where { $0.routeID.eq(#bind(routeID)) }
        .order { $0.sortIndex }
        .fetchAll(db)
      let sortIndex = sortIndex(for: siblings, after: precedingStopID)

      try Stop.insert {
        Stop(
          id: stopID,
          routeID: routeID,
          tieOut: tieOut,
          sortIndex: sortIndex,
          kind: "pointOfCall",
          displayName: displayName
        )
      }
      .execute(db)

      try rebuildSearchIndex(in: db)
    }

    return stopID
  }

  public static func updateStopDisplayName(
    _ stopID: Stop.ID,
    to displayName: String,
    in database: any DatabaseWriter
  ) throws {
    try database.write { db in
      try Stop.find(stopID)
        .update { $0.displayName = #bind(displayName) }
        .execute(db)
    }
  }

  public static func updateStopTieOut(
    _ stopID: Stop.ID,
    to tieOut: String,
    in database: any DatabaseWriter
  ) throws {
    try database.write { db in
      try Stop.find(stopID)
        .update { $0.tieOut = #bind(tieOut) }
        .execute(db)
    }
  }

  public static func deleteStop(_ stopID: Stop.ID, in database: any DatabaseWriter) throws {
    try database.write { db in
      try Stop.find(stopID)
        .delete()
        .execute(db)

      try rebuildSearchIndex(in: db)
    }
  }

  public static func addAddress(
    _ address: Address,
    toDeliveryPoint deliveryPointID: DeliveryPoint.ID,
    in database: any DatabaseWriter
  ) throws {
    try database.write { db in
      try Address.insert { address }
        .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: deliveryPointID, addressID: address.id)
      }
      .execute(db)

      try rebuildSearchIndex(in: db)
    }
  }

  public static func updateAddress(
    _ addressID: Address.ID,
    civicNumber: Int?,
    street: String,
    occupantName: String?,
    notes: String,
    in database: any DatabaseWriter
  ) throws {
    try database.write { db in
      try Address.find(addressID)
        .update {
          $0.civicNumber = #bind(civicNumber)
          $0.street = #bind(street)
          $0.occupantName = #bind(occupantName)
          $0.notes = #bind(notes)
        }
        .execute(db)

      try rebuildSearchIndex(in: db)
    }
  }

  @discardableResult
  public static func attachTag(
    named name: String,
    toAddress addressID: Address.ID,
    isWarning: Bool,
    in database: any DatabaseWriter
  ) throws -> Tag.ID {
    try database.write { db in
      let existingTag = try Tag.all.fetchAll(db).first { $0.name == name }
      let tagID: Tag.ID

      if let existingTag {
        tagID = existingTag.id
      } else {
        tagID = UUID()
        try Tag.insert {
          Tag(id: tagID, name: name, isWarning: isWarning)
        }
        .execute(db)
      }

      let isAlreadyLinked = try AddressTag.all.fetchAll(db).contains { link in
        link.addressID == addressID && link.tagID == tagID
      }

      if !isAlreadyLinked {
        try AddressTag.insert {
          AddressTag(addressID: addressID, tagID: tagID)
        }
        .execute(db)
      }

      try rebuildSearchIndex(in: db)

      return tagID
    }
  }

  public static func detachTag(
    _ tagID: Tag.ID,
    fromAddress addressID: Address.ID,
    in database: any DatabaseWriter
  ) throws {
    try database.write { db in
      let links = try AddressTag.all.fetchAll(db)
      for link in links where link.addressID == addressID && link.tagID == tagID {
        try AddressTag.find(link.id)
          .delete()
          .execute(db)
      }

      try rebuildSearchIndex(in: db)
    }
  }

  static func sortIndex(for siblings: [Stop], after precedingStopID: Stop.ID?) -> Double {
    guard
      let precedingStopID,
      let precedingIndex = siblings.firstIndex(where: { $0.id == precedingStopID })
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

  private static func rebuildSearchIndex(in db: Database) throws {
    try SearchIndex.install(db)
    try SearchIndex.rebuild(from: db)
  }
}

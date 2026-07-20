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
    var stopsCreated = 0

    try database.write { db in
      try Route.insert {
        Route(id: routeID, name: name)
      }
      .execute(db)

      var stopIDsBySite = [String: Stop.ID]()
      var moduleIDsByLocation = [String: Module.ID]()
      var deliveryPointIDsByLocation = [String: DeliveryPoint.ID]()
      var nextModuleIndexByStop = [Stop.ID: Double]()
      var tagIDsByName = [String: Tag.ID]()

      for (index, parsedStop) in result.stops.enumerated() {
        let addressID = UUID()
        let displayName = displayName(for: parsedStop)
        let siteKey = parsedStop.siteName.map(normalizedKey)
        let stopID: Stop.ID

        if let siteKey, let existingStopID = stopIDsBySite[siteKey] {
          stopID = existingStopID
        } else {
          stopID = UUID()
          stopsCreated += 1
          try Stop.insert {
            Stop(
              id: stopID,
              routeID: routeID,
              tieOut: parsedStop.tieOut ?? "",
              sortIndex: Double(index),
              kind: parsedStop.siteName == nil ? "pointOfCall" : "cmbSite",
              displayName: parsedStop.siteName ?? displayName,
              notes: parsedStop.notes ?? ""
            )
          }
          .execute(db)
          if let siteKey {
            stopIDsBySite[siteKey] = stopID
          }
        }

        let moduleID = try moduleID(
          named: parsedStop.moduleName,
          stopID: stopID,
          cache: &moduleIDsByLocation,
          nextIndex: &nextModuleIndexByStop,
          in: db
        )
        let deliveryPointID = try deliveryPointID(
          for: parsedStop,
          rowIndex: index,
          stopID: stopID,
          moduleID: moduleID,
          fallbackLabel: displayName,
          cache: &deliveryPointIDsByLocation,
          in: db
        )

        try Address.insert {
          Address(
            id: addressID,
            civicNumber: parsedStop.civicNumber,
            street: parsedStop.street,
            occupantName: parsedStop.occupantName,
            postalCode: parsedStop.postalCode,
            notes: parsedStop.notes ?? ""
          )
        }
        .execute(db)

        try DeliveryPointAddress.insert {
          DeliveryPointAddress(deliveryPointID: deliveryPointID, addressID: addressID)
        }
        .execute(db)

        for tagName in parsedStop.tags {
          try attachTag(
            named: tagName,
            isWarning: false,
            to: addressID,
            cache: &tagIDsByName,
            in: db
          )
        }
        for tagName in parsedStop.warningTags {
          try attachTag(
            named: tagName,
            isWarning: true,
            to: addressID,
            cache: &tagIDsByName,
            in: db
          )
        }
      }

      try SearchIndex.install(db)
      try SearchIndex.rebuild(from: db)
    }

    return ImportSummary(routeID: routeID, stopsCreated: stopsCreated, skipped: result.skipped)
  }

  public static func displayName(for stop: ParsedStop) -> String {
    [
      stop.civicNumber.map(String.init),
      stop.street.isEmpty ? nil : stop.street,
    ]
    .compactMap(\.self)
    .joined(separator: " ")
  }

  private static func moduleID(
    named name: String?,
    stopID: Stop.ID,
    cache: inout [String: Module.ID],
    nextIndex: inout [Stop.ID: Double],
    in db: Database
  ) throws -> Module.ID? {
    guard let name else { return nil }
    let key = "\(stopID.uuidString)|\(normalizedKey(name))"
    if let existingID = cache[key] { return existingID }

    let id = UUID()
    let sortIndex = nextIndex[stopID, default: 0]
    try Module.insert {
      Module(id: id, stopID: stopID, name: name, sortIndex: sortIndex)
    }
    .execute(db)
    cache[key] = id
    nextIndex[stopID] = sortIndex + 1
    return id
  }

  private static func deliveryPointID(
    for parsedStop: ParsedStop,
    rowIndex: Int,
    stopID: Stop.ID,
    moduleID: Module.ID?,
    fallbackLabel: String,
    cache: inout [String: DeliveryPoint.ID],
    in db: Database
  ) throws -> DeliveryPoint.ID {
    let locationKey: String
    if let compartment = parsedStop.compartmentLabel {
      locationKey = "\(stopID.uuidString)|\(moduleID?.uuidString ?? "")|\(normalizedKey(compartment))"
    } else {
      locationKey = "row|\(rowIndex)"
    }
    if let existingID = cache[locationKey] { return existingID }

    let id = UUID()
    try DeliveryPoint.insert {
      DeliveryPoint(
        id: id,
        stopID: stopID,
        moduleID: moduleID,
        kind: parsedStop.compartmentLabel == nil ? "roadsideBox" : "compartment",
        label: parsedStop.compartmentLabel ?? fallbackLabel
      )
    }
    .execute(db)
    cache[locationKey] = id
    return id
  }

  private static func attachTag(
    named name: String,
    isWarning: Bool,
    to addressID: Address.ID,
    cache: inout [String: Tag.ID],
    in db: Database
  ) throws {
    let key = normalizedKey(name)
    let tagID: Tag.ID
    if let existingID = cache[key] {
      tagID = existingID
      if isWarning {
        try Tag.find(tagID)
          .update { $0.isWarning = true }
          .execute(db)
      }
    } else {
      tagID = UUID()
      try Tag.insert { Tag(id: tagID, name: name, isWarning: isWarning) }
        .execute(db)
      cache[key] = tagID
    }

    try AddressTag.insert { AddressTag(addressID: addressID, tagID: tagID) }
      .execute(db)
  }

  private static func normalizedKey(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

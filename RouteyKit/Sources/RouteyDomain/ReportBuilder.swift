import Foundation
import SQLiteData
import RouteyModel

public struct Report: Equatable, Sendable {
  public var title: String
  public var columns: [String]
  public var rows: [[String]]

  public init(title: String, columns: [String], rows: [[String]]) {
    self.title = title
    self.columns = columns
    self.rows = rows
  }
}

public enum ReportBuilder {
  private struct Slot: Sendable {
    var stop: Stop
    var deliveryPoint: DeliveryPoint
    var module: Module?
    var addresses: [Address]
    var tagsByAddress: [Address.ID: [String]]
  }

  private struct AddressRow: Sendable {
    var slot: Slot
    var address: Address
  }

  private static let routeColumns = ["Tie-out", "Civic", "Street", "Site/Compartment", "Tags"]

  public static func tieOutSheet(
    routeID: Route.ID,
    in database: any DatabaseReader
  ) throws -> Report {
    try database.read { db in
      let rows = try slots(for: routeID, in: db).map(tieOutRow(for:))
      return Report(title: "Tie-out Sheet", columns: routeColumns, rows: rows)
    }
  }

  public static func caseStrips(
    routeID: Route.ID,
    in database: any DatabaseReader
  ) throws -> Report {
    try database.read { db in
      let rows = try slots(for: routeID, in: db).map { slot in
        [civicList(for: slot.addresses), slot.stop.tieOut, locator(for: slot)]
      }
      return Report(title: "Case Strips", columns: ["Civic", "Tie-out", "Slot"], rows: rows)
    }
  }

  /// The delivered-on filter follows Routey's per-run service date instead of timestamp bounds.
  public static func filteredList(
    routeID: Route.ID,
    tagName: String?,
    deliveredOn: Date?,
    in database: any DatabaseReader
  ) throws -> Report {
    try database.read { db in
      let slots = try slots(for: routeID, in: db)
      let deliveredAddressIDs = try deliveredAddressIDs(
        routeID: routeID,
        deliveredOn: deliveredOn,
        in: db
      )
      let addressRows = slots.flatMap { slot in
        slot.addresses.map { AddressRow(slot: slot, address: $0) }
      }
      let filteredRows = addressRows.filter { row in
        if let tagName, !(row.slot.tagsByAddress[row.address.id] ?? []).contains(tagName) {
          return false
        }
        if deliveredOn != nil, !deliveredAddressIDs.contains(row.address.id) {
          return false
        }
        return true
      }

      return Report(
        title: "Filtered List",
        columns: routeColumns,
        rows: filteredRows.map(filteredRow(for:))
      )
    }
  }

  private static func slots(for routeID: Route.ID, in db: Database) throws -> [Slot] {
    let stops = try Stop
      .where { $0.routeID.eq(#bind(routeID)) }
      .order { $0.sortIndex }
      .fetchAll(db)
    guard !stops.isEmpty else { return [] }

    let stopIDs = Set(stops.map(\.id))
    let deliveryPoints = try DeliveryPoint.all.fetchAll(db)
      .filter { stopIDs.contains($0.stopID) }
    let deliveryPointIDs = Set(deliveryPoints.map(\.id))
    let modules = try Module.all.fetchAll(db)
      .filter { stopIDs.contains($0.stopID) }
    let links = try DeliveryPointAddress.all.fetchAll(db)
      .filter { deliveryPointIDs.contains($0.deliveryPointID) }
    let addressIDs = Set(links.map(\.addressID))
    let addresses = try Address.all.fetchAll(db)
      .filter { addressIDs.contains($0.id) }
    let tagsByAddress = try tagsByAddress(in: db)

    let stopsByID = Dictionary(uniqueKeysWithValues: stops.map { ($0.id, $0) })
    let modulesByID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
    let addressesByID = Dictionary(uniqueKeysWithValues: addresses.map { ($0.id, $0) })
    let linksByDeliveryPointID = Dictionary(grouping: links, by: \.deliveryPointID)

    return deliveryPoints.compactMap { deliveryPoint in
      guard let stop = stopsByID[deliveryPoint.stopID] else { return nil }
      let slotAddresses = (linksByDeliveryPointID[deliveryPoint.id] ?? [])
        .compactMap { addressesByID[$0.addressID] }
        .sorted(by: addressComesBefore)
      return Slot(
        stop: stop,
        deliveryPoint: deliveryPoint,
        module: deliveryPoint.moduleID.flatMap { modulesByID[$0] },
        addresses: slotAddresses,
        tagsByAddress: tagsByAddress
      )
    }
    .sorted(by: slotComesBefore)
  }

  private static func tagsByAddress(in db: Database) throws -> [Address.ID: [String]] {
    let tags = try Tag.all.fetchAll(db)
    let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
    let links = try AddressTag.all.fetchAll(db)
    var result = [Address.ID: Set<String>]()

    for link in links {
      guard let tagName = tagsByID[link.tagID] else { continue }
      result[link.addressID, default: []].insert(tagName)
    }

    return result.mapValues { $0.sorted() }
  }

  private static func deliveredAddressIDs(
    routeID: Route.ID,
    deliveredOn: Date?,
    in db: Database
  ) throws -> Set<Address.ID> {
    guard let deliveredOn else { return [] }

    let serviceDate = serviceDateString(for: deliveredOn)
    let runIDs = Set(try TodaysRun.all.fetchAll(db)
      .filter { $0.routeID == routeID && $0.serviceDate == serviceDate }
      .map(\.id))

    return Set(try DeliveryRecord.all.fetchAll(db).compactMap { record in
      guard
        runIDs.contains(record.runID),
        let addressID = record.addressID
      else {
        return nil
      }
      return addressID
    })
  }

  private static func serviceDateString(for date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    let year = components.year ?? 0
    let month = components.month ?? 0
    let day = components.day ?? 0

    return "\(year)-\(twoDigit(month))-\(twoDigit(day))"
  }

  private static func twoDigit(_ value: Int) -> String {
    value < 10 ? "0\(value)" : "\(value)"
  }

  private static func tieOutRow(for slot: Slot) -> [String] {
    [
      slot.stop.tieOut,
      civicList(for: slot.addresses),
      streetList(for: slot.addresses),
      locator(for: slot),
      tagList(for: slot),
    ]
  }

  private static func filteredRow(for row: AddressRow) -> [String] {
    [
      row.slot.stop.tieOut,
      civicText(for: row.address),
      row.address.street,
      locator(for: row.slot),
      (row.slot.tagsByAddress[row.address.id] ?? []).joined(separator: ", "),
    ]
  }

  private static func civicList(for addresses: [Address]) -> String {
    addresses.map(civicText(for:)).filter { !$0.isEmpty }.joined(separator: ", ")
  }

  private static func civicText(for address: Address) -> String {
    let base: String
    if let civicNumber = address.civicNumber {
      base = "\(civicNumber)"
    } else if let from = address.civicRangeFrom, let to = address.civicRangeTo {
      base = "\(from)-\(to)"
    } else if let from = address.civicRangeFrom {
      base = "\(from)"
    } else {
      base = ""
    }

    guard let suite = address.suite, !suite.isEmpty else { return base }
    return base.isEmpty ? suite : "\(base) \(suite)"
  }

  private static func streetList(for addresses: [Address]) -> String {
    var streets = [String]()
    for street in addresses.map(\.street) where !street.isEmpty && !streets.contains(street) {
      streets.append(street)
    }
    return streets.joined(separator: ", ")
  }

  private static func locator(for slot: Slot) -> String {
    [
      siteText(for: slot.stop),
      slot.module?.name,
      slot.deliveryPoint.label,
    ]
    .compactMap { $0 }
    .filter { !$0.isEmpty }
    .joined(separator: " / ")
  }

  private static func siteText(for stop: Stop) -> String? {
    if !stop.displayName.isEmpty { return stop.displayName }
    if let officialSiteID = stop.officialSiteID, !officialSiteID.isEmpty { return officialSiteID }
    if let locationText = stop.locationText, !locationText.isEmpty { return locationText }
    return nil
  }

  private static func tagList(for slot: Slot) -> String {
    Set(slot.addresses.flatMap { slot.tagsByAddress[$0.id] ?? [] })
      .sorted()
      .joined(separator: ", ")
  }

  private static func slotComesBefore(_ lhs: Slot, _ rhs: Slot) -> Bool {
    if lhs.stop.sortIndex != rhs.stop.sortIndex {
      return lhs.stop.sortIndex < rhs.stop.sortIndex
    }

    let lhsModuleSortIndex = lhs.module?.sortIndex ?? 0
    let rhsModuleSortIndex = rhs.module?.sortIndex ?? 0
    if lhsModuleSortIndex != rhsModuleSortIndex {
      return lhsModuleSortIndex < rhsModuleSortIndex
    }

    if lhs.deliveryPoint.label != rhs.deliveryPoint.label {
      return lhs.deliveryPoint.label < rhs.deliveryPoint.label
    }

    return lhs.deliveryPoint.id.uuidString < rhs.deliveryPoint.id.uuidString
  }

  private static func addressComesBefore(_ lhs: Address, _ rhs: Address) -> Bool {
    let lhsCivic = lhs.civicNumber ?? lhs.civicRangeFrom ?? Int.max
    let rhsCivic = rhs.civicNumber ?? rhs.civicRangeFrom ?? Int.max
    if lhsCivic != rhsCivic {
      return lhsCivic < rhsCivic
    }

    if lhs.street != rhs.street {
      return lhs.street < rhs.street
    }

    return lhs.id.uuidString < rhs.id.uuidString
  }
}

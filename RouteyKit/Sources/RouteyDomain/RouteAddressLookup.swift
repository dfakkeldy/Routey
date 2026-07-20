import RouteyModel
import SQLiteData

public enum RouteAddressLookup {
  public static func addresses(
    routeID: Route.ID,
    in db: Database
  ) throws -> [Address] {
    let stopIDs = Set(
      try Stop
        .where { $0.routeID.eq(#bind(routeID)) }
        .fetchAll(db)
        .map(\.id)
    )
    let deliveryPointIDs = Set(
      try DeliveryPoint.all.fetchAll(db)
        .filter { stopIDs.contains($0.stopID) }
        .map(\.id)
    )
    let addressIDs = Set(
      try DeliveryPointAddress.all.fetchAll(db)
        .filter { deliveryPointIDs.contains($0.deliveryPointID) }
        .map(\.addressID)
    )

    return try Address
      .order { $0.street }
      .fetchAll(db)
      .filter { addressIDs.contains($0.id) }
  }

  public static func contexts(
    routeID: Route.ID,
    in db: Database
  ) throws -> [RouteAddressContext] {
    let stops = try Stop
      .where { $0.routeID.eq(#bind(routeID)) }
      .order { $0.sortIndex }
      .fetchAll(db)
    let stopByID = Dictionary(uniqueKeysWithValues: stops.map { ($0.id, $0) })
    let deliveryPoints = try DeliveryPoint.all.fetchAll(db)
      .filter { stopByID[$0.stopID] != nil }
    let pointByID = Dictionary(uniqueKeysWithValues: deliveryPoints.map { ($0.id, $0) })
    let pointIDs = Set(pointByID.keys)
    let links = try DeliveryPointAddress.all.fetchAll(db)
      .filter { pointIDs.contains($0.deliveryPointID) }
    let addressIDs = Set(links.map(\.addressID))
    let addressByID = Dictionary(
      uniqueKeysWithValues: try Address.all.fetchAll(db)
        .filter { addressIDs.contains($0.id) }
        .map { ($0.id, $0) }
    )
    let moduleByID = Dictionary(
      uniqueKeysWithValues: try Module.all.fetchAll(db).map { ($0.id, $0) }
    )
    let tagByID = Dictionary(
      uniqueKeysWithValues: try Tag.all.fetchAll(db).map { ($0.id, $0) }
    )
    let tagLinks = try AddressTag.all.fetchAll(db)
      .filter { addressIDs.contains($0.addressID) }
    var tagsByAddressID = [Address.ID: [Tag]]()
    for link in tagLinks {
      if let tag = tagByID[link.tagID] {
        tagsByAddressID[link.addressID, default: []].append(tag)
      }
    }

    var seenAddressIDs = Set<Address.ID>()
    return links.compactMap { link in
      guard
        seenAddressIDs.insert(link.addressID).inserted,
        let point = pointByID[link.deliveryPointID],
        let stop = stopByID[point.stopID],
        let address = addressByID[link.addressID]
      else { return nil }

      let tags = tagsByAddressID[address.id, default: []]
        .sorted { $0.name < $1.name }
      return RouteAddressContext(
        address: address,
        siteName: stop.kind == "cmbSite" && !stop.displayName.isEmpty ? stop.displayName : nil,
        moduleName: point.moduleID.flatMap { moduleByID[$0]?.name },
        compartmentLabel: point.kind == "compartment" && !point.label.isEmpty ? point.label : nil,
        driveOrder: stop.tieOut.isEmpty ? nil : stop.tieOut,
        tagNames: tags.map(\.name),
        warningTagNames: tags.filter(\.isWarning).map(\.name)
      )
    }
    .sorted { lhs, rhs in
      (lhs.address.street, lhs.address.civicNumber ?? 0, lhs.address.id.uuidString)
        < (rhs.address.street, rhs.address.civicNumber ?? 0, rhs.address.id.uuidString)
    }
  }
}

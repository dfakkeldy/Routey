import Foundation
import SQLiteData
import RouteyModel

public struct AddressResolutionCandidate: Equatable, Sendable {
  public var addressID: Address.ID
  public var stopID: Stop.ID
  public var query: String

  public init(addressID: Address.ID, stopID: Stop.ID, query: String) {
    self.addressID = addressID
    self.stopID = stopID
    self.query = query
  }
}

public enum CoordinateResolution {
  public static func candidates(
    routeID: Route.ID,
    in database: any DatabaseReader
  ) throws -> [AddressResolutionCandidate] {
    try database.read { db in
      try candidates(routeID: routeID, in: db)
    }
  }

  private static func candidates(
    routeID: Route.ID,
    in db: Database
  ) throws -> [AddressResolutionCandidate] {
    let stops = try Stop
      .where { $0.routeID.eq(#bind(routeID)) }
      .order { $0.sortIndex }
      .fetchAll(db)
    let stopIDs = Set(stops.map(\.id))

    let deliveryPoints = try DeliveryPoint.all.fetchAll(db)
      .filter { stopIDs.contains($0.stopID) }
    let deliveryPointsByStop = Dictionary(grouping: deliveryPoints, by: \.stopID)
    let deliveryPointIDs = Set(deliveryPoints.map(\.id))

    let links = try DeliveryPointAddress.all.fetchAll(db)
      .filter { deliveryPointIDs.contains($0.deliveryPointID) }
    let linksByDeliveryPoint = Dictionary(grouping: links, by: \.deliveryPointID)
    let addressIDs = Set(links.map(\.addressID))

    let addressesByID = Dictionary(
      uniqueKeysWithValues: try Address.all.fetchAll(db)
        .filter { addressIDs.contains($0.id) }
        .map { ($0.id, $0) }
    )

    var seenAddressIDs: Set<Address.ID> = []
    var candidates: [AddressResolutionCandidate] = []

    for stop in stops {
      let points = deliveryPointsByStop[stop.id, default: []].sorted {
        ($0.label, $0.id.uuidString) < ($1.label, $1.id.uuidString)
      }

      for point in points {
        let pointLinks = linksByDeliveryPoint[point.id, default: []].sorted {
          $0.id.uuidString < $1.id.uuidString
        }

        for link in pointLinks where !seenAddressIDs.contains(link.addressID) {
          seenAddressIDs.insert(link.addressID)
          guard
            let address = addressesByID[link.addressID],
            address.doorLatitude == nil || address.doorLongitude == nil
          else {
            continue
          }

          let query = query(for: address)
          if !query.isEmpty {
            candidates.append(
              AddressResolutionCandidate(addressID: address.id, stopID: stop.id, query: query)
            )
          }
        }
      }
    }

    return candidates
  }

  private static func query(for address: Address) -> String {
    var pieces: [String] = []

    if let civicNumber = address.civicNumber {
      pieces.append(civicNumber.formatted(.number.grouping(.never)))
    } else if let rangeFrom = address.civicRangeFrom, let rangeTo = address.civicRangeTo {
      pieces.append([
        rangeFrom.formatted(.number.grouping(.never)),
        rangeTo.formatted(.number.grouping(.never)),
      ].joined(separator: "-"))
    }

    if !address.street.isEmpty {
      pieces.append(address.street)
    }

    if let postalCode = address.postalCode, !postalCode.isEmpty {
      pieces.append(postalCode)
    }

    return pieces.joined(separator: " ")
  }
}

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
}

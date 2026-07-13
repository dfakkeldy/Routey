import RouteyModel
import SQLiteData

enum RunAddressLookup {
  static func contains(
    _ addressID: Address.ID,
    runID: TodaysRun.ID,
    in db: Database
  ) throws -> Bool {
    let stopIDs = Set(
      try RunStop
        .where { $0.runID.eq(#bind(runID)) }
        .fetchAll(db)
        .compactMap(\.stopID)
    )
    let deliveryPointIDs = Set(
      try DeliveryPoint.all.fetchAll(db)
        .filter { stopIDs.contains($0.stopID) }
        .map(\.id)
    )

    return try DeliveryPointAddress
      .where { $0.addressID.eq(#bind(addressID)) }
      .fetchAll(db)
      .contains { deliveryPointIDs.contains($0.deliveryPointID) }
  }
}

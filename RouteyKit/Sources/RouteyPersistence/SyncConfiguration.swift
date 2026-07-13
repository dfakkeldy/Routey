import RouteyModel
import SQLiteData

public func routeySyncEngine(for database: any DatabaseWriter) throws -> SyncEngine {
  try SyncEngine(
    for: database,
    privateTables: Route.self, Stop.self, Module.self, DeliveryPoint.self,
    Address.self, Tag.self, DeliveryPointAddress.self, AddressTag.self,
    TodaysRun.self, RunStop.self, Parcel.self, DeliveryRecord.self, FollowUpTask.self
  )
}

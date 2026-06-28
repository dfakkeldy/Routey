import Foundation
import SQLiteData
import RouteyModel

public enum RouteExporter {
  public static let payloadSchemaVersion: UInt16 = 1
  public static let defaultIterations: UInt32 = 600_000

  public static func export(
    routeID: Route.ID,
    passphrase: String,
    iterations: UInt32 = defaultIterations,
    from database: any DatabaseReader
  ) throws -> Data {
    let dto = try DTOMapping.buildDTO(routeID: routeID, from: database)
    let payload = try JSONEncoder().encode(dto)
    return try RouteyCrypto.encrypt(
      payload,
      passphrase: passphrase,
      payloadSchemaVersion: payloadSchemaVersion,
      iterations: iterations
    )
  }
}

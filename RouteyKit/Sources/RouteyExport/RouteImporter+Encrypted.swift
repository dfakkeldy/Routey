import Foundation
import SQLiteData
import RouteyModel

public enum EncryptedRouteImporterError: Error, Equatable {
  case unsupportedPayloadSchemaVersion(UInt16)
}

public enum EncryptedRouteImporter {
  private static let supportedPayloadSchemaVersion: UInt16 = 1

  public static func `import`(
    _ data: Data,
    passphrase: String,
    into database: any DatabaseWriter
  ) throws -> Route.ID {
    let decrypted = try RouteyCrypto.decrypt(data, passphrase: passphrase)
    guard decrypted.payloadSchemaVersion <= supportedPayloadSchemaVersion else {
      throw EncryptedRouteImporterError.unsupportedPayloadSchemaVersion(decrypted.payloadSchemaVersion)
    }

    let dto = try JSONDecoder().decode(RouteExportDTO.self, from: decrypted.plaintext)
    return try DTOMapping.insert(dto, asBorrowed: true, into: database)
  }
}

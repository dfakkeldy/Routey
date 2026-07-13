import Foundation
import Testing
@testable import RouteyExport

@Suite struct RouteyCryptoTests {
  private let iterations: UInt32 = 100_000

  @Test func roundTripsPlaintextAndPayloadSchemaVersion() throws {
    let plaintext = Data("hello route".utf8)

    let blob = try RouteyCrypto.encrypt(
      plaintext,
      passphrase: "correct horse",
      payloadSchemaVersion: 1,
      iterations: iterations
    )
    let result = try RouteyCrypto.decrypt(blob, passphrase: "correct horse")

    #expect(result.plaintext == plaintext)
    #expect(result.payloadSchemaVersion == 1)
  }

  @Test func wrongPassphraseMapsToWrongPassphraseOrCorrupt() throws {
    let blob = try RouteyCrypto.encrypt(
      Data("x".utf8),
      passphrase: "right",
      payloadSchemaVersion: 1,
      iterations: iterations
    )

    #expect(throws: RouteyCryptoError.wrongPassphraseOrCorrupt) {
      _ = try RouteyCrypto.decrypt(blob, passphrase: "wrong")
    }
  }

  @Test func ciphertextOrTagTamperMapsToWrongPassphraseOrCorrupt() throws {
    var blob = try RouteyCrypto.encrypt(
      Data("x".utf8),
      passphrase: "p",
      payloadSchemaVersion: 1,
      iterations: iterations
    )
    blob[blob.count - 1] ^= 0xFF

    #expect(throws: RouteyCryptoError.wrongPassphraseOrCorrupt) {
      _ = try RouteyCrypto.decrypt(blob, passphrase: "p")
    }
  }

  @Test func authenticatedHeaderTamperMapsToWrongPassphraseOrCorrupt() throws {
    var blob = try RouteyCrypto.encrypt(
      Data("x".utf8),
      passphrase: "p",
      payloadSchemaVersion: 1,
      iterations: iterations
    )
    let payloadSchemaLowByteOffset = 28
    blob[payloadSchemaLowByteOffset] ^= 0xFF

    #expect(throws: RouteyCryptoError.wrongPassphraseOrCorrupt) {
      _ = try RouteyCrypto.decrypt(blob, passphrase: "p")
    }
  }

  @Test func badMagicFailsAsBadFormat() {
    #expect(throws: RouteyCryptoError.badFormat) {
      _ = try RouteyCrypto.decrypt(Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]), passphrase: "p")
    }
  }

  @Test func saltAndNonceAreRandomPerExport() throws {
    let first = try RouteyCrypto.encrypt(
      Data("x".utf8),
      passphrase: "p",
      payloadSchemaVersion: 1,
      iterations: iterations
    )
    let second = try RouteyCrypto.encrypt(
      Data("x".utf8),
      passphrase: "p",
      payloadSchemaVersion: 1,
      iterations: iterations
    )

    #expect(first != second)
  }
}

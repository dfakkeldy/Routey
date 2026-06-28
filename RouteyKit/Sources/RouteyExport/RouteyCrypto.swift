import CommonCrypto
import CryptoKit
import Foundation
import Security

public enum RouteyCryptoError: Error, Equatable {
  case badFormat
  case unsupportedVersion(UInt8)
  case wrongPassphraseOrCorrupt
}

public enum RouteyCrypto {
  private static let magic = Data("RTYE".utf8)
  private static let formatVersion: UInt8 = 1
  private static let kdfPBKDF2SHA256: UInt8 = 1
  private static let saltLength = 16
  private static let nonceLength = 12
  private static let tagLength = 16
  private static let keyLength = 32

  public static func encrypt(
    _ plaintext: Data,
    passphrase: String,
    payloadSchemaVersion: UInt16,
    iterations: UInt32
  ) throws -> Data {
    let salt = try randomBytes(count: saltLength)
    let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)

    var header = Data()
    header.append(magic)
    header.append(formatVersion)
    header.append(kdfPBKDF2SHA256)
    appendBigEndian(iterations, to: &header)
    header.append(UInt8(salt.count))
    header.append(salt)
    appendBigEndian(payloadSchemaVersion, to: &header)

    let nonce = AES.GCM.Nonce()
    let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: header)

    var output = header
    output.append(contentsOf: nonce)
    output.append(sealed.ciphertext)
    output.append(sealed.tag)
    return output
  }

  public static func decrypt(_ data: Data, passphrase: String) throws -> (
    plaintext: Data,
    payloadSchemaVersion: UInt16
  ) {
    var index = data.startIndex

    let parsedMagic = try take(4, from: data, index: &index)
    guard parsedMagic == magic else { throw RouteyCryptoError.badFormat }

    let parsedFormat = try takeByte(from: data, index: &index)
    guard parsedFormat == formatVersion else {
      throw RouteyCryptoError.unsupportedVersion(parsedFormat)
    }

    let parsedKDF = try takeByte(from: data, index: &index)
    guard parsedKDF == kdfPBKDF2SHA256 else {
      throw RouteyCryptoError.unsupportedVersion(parsedKDF)
    }

    let iterations = UInt32(bigEndianData: try take(4, from: data, index: &index))
    let parsedSaltLength = Int(try takeByte(from: data, index: &index))
    guard parsedSaltLength > 0 else { throw RouteyCryptoError.badFormat }
    let salt = try take(parsedSaltLength, from: data, index: &index)
    let payloadSchemaVersion = UInt16(bigEndianData: try take(2, from: data, index: &index))

    let header = data[data.startIndex..<index]
    let body = data[index...]
    guard body.count >= nonceLength + tagLength else { throw RouteyCryptoError.badFormat }

    let nonceData = body.prefix(nonceLength)
    let ciphertextAndTag = body.dropFirst(nonceLength)
    let ciphertext = ciphertextAndTag.dropLast(tagLength)
    let tag = ciphertextAndTag.suffix(tagLength)
    let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)

    do {
      let nonce = try AES.GCM.Nonce(data: nonceData)
      let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
      let plaintext = try AES.GCM.open(box, using: key, authenticating: header)
      return (plaintext, payloadSchemaVersion)
    } catch {
      throw RouteyCryptoError.wrongPassphraseOrCorrupt
    }
  }

  private static func randomBytes(count: Int) throws -> Data {
    var data = Data(count: count)
    let status = try data.withUnsafeMutableBytes { rawBuffer -> OSStatus in
      guard let baseAddress = rawBuffer.baseAddress else {
        throw RouteyCryptoError.badFormat
      }
      return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
    }
    guard status == errSecSuccess else { throw RouteyCryptoError.badFormat }
    return data
  }

  private static func deriveKey(passphrase: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
    let passwordLength = passphrase.utf8.count
    var derived = Data(count: keyLength)

    let status = try derived.withUnsafeMutableBytes { derivedRawBuffer -> Int32 in
      guard let derivedBaseAddress = derivedRawBuffer.bindMemory(to: UInt8.self).baseAddress else {
        throw RouteyCryptoError.badFormat
      }

      return salt.withUnsafeBytes { saltRawBuffer in
        passphrase.withCString { passwordPointer in
          CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordPointer,
            passwordLength,
            saltRawBuffer.bindMemory(to: UInt8.self).baseAddress,
            salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            iterations,
            derivedBaseAddress,
            keyLength
          )
        }
      }
    }

    guard status == kCCSuccess else { throw RouteyCryptoError.badFormat }
    return SymmetricKey(data: derived)
  }

  private static func take(_ count: Int, from data: Data, index: inout Data.Index) throws -> Data.SubSequence {
    guard count >= 0, data.distance(from: index, to: data.endIndex) >= count else {
      throw RouteyCryptoError.badFormat
    }

    let endIndex = data.index(index, offsetBy: count)
    defer { index = endIndex }
    return data[index..<endIndex]
  }

  private static func takeByte(from data: Data, index: inout Data.Index) throws -> UInt8 {
    guard let byte = try take(1, from: data, index: &index).first else {
      throw RouteyCryptoError.badFormat
    }
    return byte
  }

  private static func appendBigEndian(_ value: UInt32, to data: inout Data) {
    data.append(contentsOf: [
      UInt8((value >> 24) & 0xFF),
      UInt8((value >> 16) & 0xFF),
      UInt8((value >> 8) & 0xFF),
      UInt8(value & 0xFF),
    ])
  }

  private static func appendBigEndian(_ value: UInt16, to data: inout Data) {
    data.append(contentsOf: [
      UInt8((value >> 8) & 0xFF),
      UInt8(value & 0xFF),
    ])
  }
}

private extension UInt32 {
  init(bigEndianData data: Data.SubSequence) {
    self = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
  }
}

private extension UInt16 {
  init(bigEndianData data: Data.SubSequence) {
    self = data.reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
  }
}

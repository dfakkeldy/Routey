import Foundation

public struct SnapParcelInput: Equatable, Sendable {
  public var addressID: UUID?
  public var source: String
  public var requiresSignature: Bool
  public var isCustoms: Bool
  public var toDoor: Bool
  public var labelSnapshot: String
  public var trackingCode: String
  public var trackingSymbology: String

  public init(
    addressID: UUID?,
    source: String,
    requiresSignature: Bool,
    isCustoms: Bool,
    toDoor: Bool,
    labelSnapshot: String,
    trackingCode: String,
    trackingSymbology: String
  ) {
    self.addressID = addressID
    self.source = source
    self.requiresSignature = requiresSignature
    self.isCustoms = isCustoms
    self.toDoor = toDoor
    self.labelSnapshot = labelSnapshot
    self.trackingCode = trackingCode
    self.trackingSymbology = trackingSymbology
  }
}

public enum SnapToAdd {
  public static func parcelInputs(from result: SnapMatchResult, addressID: UUID?) -> SnapParcelInput {
    SnapParcelInput(
      addressID: addressID,
      source: "ocr",
      requiresSignature: result.flags.contains(.signature),
      isCustoms: result.flags.contains(.customs),
      toDoor: false,
      labelSnapshot: result.readout.lines.joined(separator: "\n"),
      trackingCode: result.readout.barcodes.first ?? "",
      trackingSymbology: ""
    )
  }
}

import Foundation
import SQLiteData

@Table
public nonisolated struct Parcel: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var runID: TodaysRun.ID
  public var addressID: Address.ID? = nil
  public var source = "manual"
  public var sizeClass = ""
  public var toDoor = false
  public var requiresSignature = false
  public var isCustoms = false
  public var isDelivered = false
  public var labelSnapshot = ""
  public var trackingCode = ""
  public var trackingSymbology = ""

  public init(
    id: UUID = UUID(),
    runID: TodaysRun.ID,
    addressID: Address.ID? = nil,
    source: String = "manual",
    sizeClass: String = "",
    toDoor: Bool = false,
    requiresSignature: Bool = false,
    isCustoms: Bool = false,
    isDelivered: Bool = false,
    labelSnapshot: String = "",
    trackingCode: String = "",
    trackingSymbology: String = ""
  ) {
    self.id = id
    self.runID = runID
    self.addressID = addressID
    self.source = source
    self.sizeClass = sizeClass
    self.toDoor = toDoor
    self.requiresSignature = requiresSignature
    self.isCustoms = isCustoms
    self.isDelivered = isDelivered
    self.labelSnapshot = labelSnapshot
    self.trackingCode = trackingCode
    self.trackingSymbology = trackingSymbology
  }
}

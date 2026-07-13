import Foundation
import SQLiteData

@Table
public nonisolated struct DeliveryRecord: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var runID: TodaysRun.ID
  public var addressID: Address.ID? = nil
  public var parcelID: Parcel.ID? = nil
  public var outcome = ""
  public var latitude: Double? = nil
  public var longitude: Double? = nil
  public var loggedAt: Date = Date(timeIntervalSinceReferenceDate: 0)
  public var photoPath: String? = nil

  public init(
    id: UUID = UUID(),
    runID: TodaysRun.ID,
    addressID: Address.ID? = nil,
    parcelID: Parcel.ID? = nil,
    outcome: String = "",
    latitude: Double? = nil,
    longitude: Double? = nil,
    loggedAt: Date = Date(timeIntervalSinceReferenceDate: 0),
    photoPath: String? = nil
  ) {
    self.id = id
    self.runID = runID
    self.addressID = addressID
    self.parcelID = parcelID
    self.outcome = outcome
    self.latitude = latitude
    self.longitude = longitude
    self.loggedAt = loggedAt
    self.photoPath = photoPath
  }
}

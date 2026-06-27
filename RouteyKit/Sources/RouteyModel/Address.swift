import Foundation
import SQLiteData

@Table
public nonisolated struct Address: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var civicNumber: Int? = nil
  public var civicRangeFrom: Int? = nil
  public var civicRangeTo: Int? = nil
  public var suite: String? = nil
  public var street = ""
  public var occupantName: String? = nil   // disambiguates multi-unit / complexes
  public var doorLatitude: Double? = nil
  public var doorLongitude: Double? = nil
  public var postalCode: String? = nil
  public var notes = ""
  public init(
    id: UUID = UUID(), civicNumber: Int? = nil, civicRangeFrom: Int? = nil,
    civicRangeTo: Int? = nil, suite: String? = nil, street: String = "",
    occupantName: String? = nil, doorLatitude: Double? = nil, doorLongitude: Double? = nil,
    postalCode: String? = nil, notes: String = ""
  ) {
    self.id = id; self.civicNumber = civicNumber; self.civicRangeFrom = civicRangeFrom
    self.civicRangeTo = civicRangeTo; self.suite = suite; self.street = street
    self.occupantName = occupantName; self.doorLatitude = doorLatitude
    self.doorLongitude = doorLongitude; self.postalCode = postalCode; self.notes = notes
  }
}

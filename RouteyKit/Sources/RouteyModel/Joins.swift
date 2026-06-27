import Foundation
import SQLiteData

// Shared boxes/compartments: one DeliveryPoint serves many Addresses (many-to-many).
@Table
public nonisolated struct DeliveryPointAddress: Identifiable, Sendable {
  public let id: UUID
  public var deliveryPointID: DeliveryPoint.ID
  public var addressID: Address.ID
  public init(id: UUID = UUID(), deliveryPointID: DeliveryPoint.ID, addressID: Address.ID) {
    self.id = id; self.deliveryPointID = deliveryPointID; self.addressID = addressID
  }
}

// Address <-> Tag (many-to-many).
@Table
public nonisolated struct AddressTag: Identifiable, Sendable {
  public let id: UUID
  public var addressID: Address.ID
  public var tagID: Tag.ID
  public init(id: UUID = UUID(), addressID: Address.ID, tagID: Tag.ID) {
    self.id = id; self.addressID = addressID; self.tagID = tagID
  }
}

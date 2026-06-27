import Foundation
import SQLiteData

@Table
public nonisolated struct DeliveryPoint: Identifiable, Sendable {
  public let id: UUID
  public var stopID: Stop.ID
  public var moduleID: Module.ID? = nil
  public var kind = "roadsideBox"     // roadsideBox | compartment
  public var label = ""
  public var isParcelLocker = false
  public var status = "active"        // active | vacant | closed
  public var notes = ""
  public init(
    id: UUID = UUID(), stopID: Stop.ID, moduleID: Module.ID? = nil,
    kind: String = "roadsideBox", label: String = "", isParcelLocker: Bool = false,
    status: String = "active", notes: String = ""
  ) {
    self.id = id; self.stopID = stopID; self.moduleID = moduleID; self.kind = kind
    self.label = label; self.isParcelLocker = isParcelLocker; self.status = status; self.notes = notes
  }
}

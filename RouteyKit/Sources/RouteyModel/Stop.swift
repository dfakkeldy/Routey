import Foundation
import SQLiteData

@Table
public nonisolated struct Stop: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var routeID: Route.ID
  public var tieOut = ""
  public var sortIndex = 0.0          // fractional/gap index for cheap reordering
  public var kind = "pointOfCall"     // pointOfCall | rmbCluster | cmbSite | doorVisit
  public var displayName = ""         // nickname: "Cornerstore", "The Manor"
  public var officialSiteID: String? = nil
  public var locationText: String? = nil
  public var sharesLocationWith: String? = nil
  public var latitude: Double? = nil
  public var longitude: Double? = nil
  public var notes = ""
  public init(
    id: UUID = UUID(), routeID: Route.ID, tieOut: String = "", sortIndex: Double = 0,
    kind: String = "pointOfCall", displayName: String = "", officialSiteID: String? = nil,
    locationText: String? = nil, sharesLocationWith: String? = nil,
    latitude: Double? = nil, longitude: Double? = nil, notes: String = ""
  ) {
    self.id = id; self.routeID = routeID; self.tieOut = tieOut; self.sortIndex = sortIndex
    self.kind = kind; self.displayName = displayName; self.officialSiteID = officialSiteID
    self.locationText = locationText; self.sharesLocationWith = sharesLocationWith
    self.latitude = latitude; self.longitude = longitude; self.notes = notes
  }
}

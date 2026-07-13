import Foundation

public struct RouteExportDTO: Codable, Equatable, Sendable {
  public var route: RouteDTO
  public var stops: [StopDTO]
  public var modules: [ModuleDTO]
  public var deliveryPoints: [DeliveryPointDTO]
  public var addresses: [AddressDTO]
  public var tags: [TagDTO]
  public var deliveryPointAddresses: [DeliveryPointAddressDTO]
  public var addressTags: [AddressTagDTO]

  public init(
    route: RouteDTO,
    stops: [StopDTO] = [],
    modules: [ModuleDTO] = [],
    deliveryPoints: [DeliveryPointDTO] = [],
    addresses: [AddressDTO] = [],
    tags: [TagDTO] = [],
    deliveryPointAddresses: [DeliveryPointAddressDTO] = [],
    addressTags: [AddressTagDTO] = []
  ) {
    self.route = route
    self.stops = stops
    self.modules = modules
    self.deliveryPoints = deliveryPoints
    self.addresses = addresses
    self.tags = tags
    self.deliveryPointAddresses = deliveryPointAddresses
    self.addressTags = addressTags
  }

  public struct RouteDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var rtaFSA: String
    public var isBorrowed: Bool

    public init(id: UUID, name: String, rtaFSA: String, isBorrowed: Bool) {
      self.id = id
      self.name = name
      self.rtaFSA = rtaFSA
      self.isBorrowed = isBorrowed
    }
  }

  public struct StopDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var routeID: UUID
    public var tieOut: String
    public var sortIndex: Double
    public var kind: String
    public var displayName: String
    public var officialSiteID: String?
    public var locationText: String?
    public var sharesLocationWith: String?
    public var latitude: Double?
    public var longitude: Double?
    public var notes: String

    public init(
      id: UUID,
      routeID: UUID,
      tieOut: String,
      sortIndex: Double,
      kind: String,
      displayName: String,
      officialSiteID: String?,
      locationText: String?,
      sharesLocationWith: String?,
      latitude: Double?,
      longitude: Double?,
      notes: String
    ) {
      self.id = id
      self.routeID = routeID
      self.tieOut = tieOut
      self.sortIndex = sortIndex
      self.kind = kind
      self.displayName = displayName
      self.officialSiteID = officialSiteID
      self.locationText = locationText
      self.sharesLocationWith = sharesLocationWith
      self.latitude = latitude
      self.longitude = longitude
      self.notes = notes
    }
  }

  public struct ModuleDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var stopID: UUID
    public var name: String
    public var sortIndex: Double

    public init(id: UUID, stopID: UUID, name: String, sortIndex: Double) {
      self.id = id
      self.stopID = stopID
      self.name = name
      self.sortIndex = sortIndex
    }
  }

  public struct DeliveryPointDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var stopID: UUID
    public var moduleID: UUID?
    public var kind: String
    public var label: String
    public var isParcelLocker: Bool
    public var status: String
    public var notes: String

    public init(
      id: UUID,
      stopID: UUID,
      moduleID: UUID?,
      kind: String,
      label: String,
      isParcelLocker: Bool,
      status: String,
      notes: String
    ) {
      self.id = id
      self.stopID = stopID
      self.moduleID = moduleID
      self.kind = kind
      self.label = label
      self.isParcelLocker = isParcelLocker
      self.status = status
      self.notes = notes
    }
  }

  public struct AddressDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var civicNumber: Int?
    public var civicRangeFrom: Int?
    public var civicRangeTo: Int?
    public var suite: String?
    public var street: String
    public var occupantName: String?
    public var doorLatitude: Double?
    public var doorLongitude: Double?
    public var postalCode: String?
    public var notes: String

    public init(
      id: UUID,
      civicNumber: Int?,
      civicRangeFrom: Int?,
      civicRangeTo: Int?,
      suite: String?,
      street: String,
      occupantName: String?,
      doorLatitude: Double?,
      doorLongitude: Double?,
      postalCode: String?,
      notes: String
    ) {
      self.id = id
      self.civicNumber = civicNumber
      self.civicRangeFrom = civicRangeFrom
      self.civicRangeTo = civicRangeTo
      self.suite = suite
      self.street = street
      self.occupantName = occupantName
      self.doorLatitude = doorLatitude
      self.doorLongitude = doorLongitude
      self.postalCode = postalCode
      self.notes = notes
    }
  }

  public struct TagDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var isWarning: Bool

    public init(id: UUID, name: String, isWarning: Bool) {
      self.id = id
      self.name = name
      self.isWarning = isWarning
    }
  }

  public struct DeliveryPointAddressDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var deliveryPointID: UUID
    public var addressID: UUID

    public init(id: UUID, deliveryPointID: UUID, addressID: UUID) {
      self.id = id
      self.deliveryPointID = deliveryPointID
      self.addressID = addressID
    }
  }

  public struct AddressTagDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var addressID: UUID
    public var tagID: UUID

    public init(id: UUID, addressID: UUID, tagID: UUID) {
      self.id = id
      self.addressID = addressID
      self.tagID = tagID
    }
  }
}

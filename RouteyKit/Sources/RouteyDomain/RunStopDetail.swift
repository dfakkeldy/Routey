import Foundation
import RouteyModel
import SQLiteData

public struct RunStopDetail: Equatable, Sendable {
  public struct AddressLine: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var civic: String
    public var street: String
    public var occupant: String?

    public init(id: UUID, civic: String, street: String, occupant: String?) {
      self.id = id
      self.civic = civic
      self.street = street
      self.occupant = occupant
    }
  }

  public struct ParcelLine: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var labelSnapshot: String
    public var trackingCode: String
    public var requiresSignature: Bool
    public var isCustoms: Bool
    public var isDelivered: Bool

    public init(
      id: UUID,
      labelSnapshot: String,
      trackingCode: String,
      requiresSignature: Bool,
      isCustoms: Bool,
      isDelivered: Bool
    ) {
      self.id = id
      self.labelSnapshot = labelSnapshot
      self.trackingCode = trackingCode
      self.requiresSignature = requiresSignature
      self.isCustoms = isCustoms
      self.isDelivered = isDelivered
    }
  }

  public var addresses: [AddressLine]
  public var parcels: [ParcelLine]
  public var warningTags: [String]

  public init(
    addresses: [AddressLine] = [],
    parcels: [ParcelLine] = [],
    warningTags: [String] = []
  ) {
    self.addresses = addresses
    self.parcels = parcels
    self.warningTags = warningTags
  }

  public static let empty = RunStopDetail()

  public static func load(
    runStopID: RunStop.ID,
    runID: TodaysRun.ID,
    _ db: Database
  ) throws -> RunStopDetail {
    guard let runStop = try RunStop.find(runStopID).fetchOne(db), let stopID = runStop.stopID else {
      return .empty
    }

    let deliveryPoints = try DeliveryPoint
      .where { $0.stopID.eq(#bind(stopID)) }
      .fetchAll(db)
    let deliveryPointIDs = Set(deliveryPoints.map(\.id))
    let links = try DeliveryPointAddress.all.fetchAll(db)
      .filter { deliveryPointIDs.contains($0.deliveryPointID) }
    let addressIDs = Set(links.map(\.addressID))
    let addresses = try Address.all.fetchAll(db)
      .filter { addressIDs.contains($0.id) }
    let addressTags = try AddressTag.all.fetchAll(db)
      .filter { addressIDs.contains($0.addressID) }
    let tagIDs = Set(addressTags.map(\.tagID))
    let warningTags = try Tag.all.fetchAll(db)
      .filter { $0.isWarning && tagIDs.contains($0.id) }
      .map(\.name)
      .sorted()
    let parcels = try Parcel
      .where { $0.runID.eq(#bind(runID)) }
      .fetchAll(db)
      .filter { parcel in
        parcel.addressID.map { addressIDs.contains($0) } ?? false
      }

    return RunStopDetail(
      addresses: addresses
        .sorted { lhs, rhs in
          (lhs.civicNumber ?? 0, lhs.street) < (rhs.civicNumber ?? 0, rhs.street)
        }
        .map { address in
          AddressLine(
            id: address.id,
            civic: civicDisplay(address),
            street: address.street,
            occupant: address.occupantName
          )
        },
      parcels: parcels.map { parcel in
        ParcelLine(
          id: parcel.id,
          labelSnapshot: parcel.labelSnapshot,
          trackingCode: parcel.trackingCode,
          requiresSignature: parcel.requiresSignature,
          isCustoms: parcel.isCustoms,
          isDelivered: parcel.isDelivered
        )
      },
      warningTags: warningTags
    )
  }

  private static func civicDisplay(_ address: Address) -> String {
    if let civicNumber = address.civicNumber {
      return civicNumber.formatted(.number.grouping(.never))
    }
    if let rangeFrom = address.civicRangeFrom, let rangeTo = address.civicRangeTo {
      return [
        rangeFrom.formatted(.number.grouping(.never)),
        rangeTo.formatted(.number.grouping(.never)),
      ]
      .joined(separator: "-")
    }
    return ""
  }
}

import Foundation
import SQLiteData
import RouteyModel

public enum DTOMappingError: Error, Equatable {
  case routeNotFound
  case malformedGraph
}

public enum DTOMapping {
  public static func buildDTO(routeID: Route.ID, from database: any DatabaseReader) throws -> RouteExportDTO {
    try database.read { db in
      let route = try Route.all.fetchAll(db).first { $0.id == routeID }
      guard let route else { throw DTOMappingError.routeNotFound }

      let stops = try Stop.all.fetchAll(db)
        .filter { $0.routeID == routeID }
        .sorted { lhs, rhs in
          (lhs.sortIndex, lhs.displayName, lhs.id.uuidString) < (rhs.sortIndex, rhs.displayName, rhs.id.uuidString)
        }
      let stopIDs = Set(stops.map(\.id))

      let modules = try Module.all.fetchAll(db)
        .filter { stopIDs.contains($0.stopID) }
        .sorted { lhs, rhs in
          (lhs.stopID.uuidString, lhs.sortIndex, lhs.name, lhs.id.uuidString)
            < (rhs.stopID.uuidString, rhs.sortIndex, rhs.name, rhs.id.uuidString)
        }

      let deliveryPoints = try DeliveryPoint.all.fetchAll(db)
        .filter { stopIDs.contains($0.stopID) }
        .sorted { lhs, rhs in
          (
            lhs.stopID.uuidString,
            lhs.moduleID?.uuidString ?? "",
            lhs.label,
            lhs.id.uuidString
          ) < (
            rhs.stopID.uuidString,
            rhs.moduleID?.uuidString ?? "",
            rhs.label,
            rhs.id.uuidString
          )
        }
      let deliveryPointIDs = Set(deliveryPoints.map(\.id))

      let deliveryPointAddresses = try DeliveryPointAddress.all.fetchAll(db)
        .filter { deliveryPointIDs.contains($0.deliveryPointID) }
        .sorted { lhs, rhs in
          (lhs.deliveryPointID.uuidString, lhs.addressID.uuidString, lhs.id.uuidString)
            < (rhs.deliveryPointID.uuidString, rhs.addressID.uuidString, rhs.id.uuidString)
        }
      let addressIDs = Set(deliveryPointAddresses.map(\.addressID))

      let addresses = try Address.all.fetchAll(db)
        .filter { addressIDs.contains($0.id) }
        .sorted { lhs, rhs in
          (
            lhs.street,
            lhs.civicNumber ?? -1,
            lhs.suite ?? "",
            lhs.id.uuidString
          ) < (
            rhs.street,
            rhs.civicNumber ?? -1,
            rhs.suite ?? "",
            rhs.id.uuidString
          )
        }

      let addressTags = try AddressTag.all.fetchAll(db)
        .filter { addressIDs.contains($0.addressID) }
        .sorted { lhs, rhs in
          (lhs.addressID.uuidString, lhs.tagID.uuidString, lhs.id.uuidString)
            < (rhs.addressID.uuidString, rhs.tagID.uuidString, rhs.id.uuidString)
        }
      let tagIDs = Set(addressTags.map(\.tagID))

      let tags = try Tag.all.fetchAll(db)
        .filter { tagIDs.contains($0.id) }
        .sorted { lhs, rhs in
          (lhs.name, lhs.id.uuidString) < (rhs.name, rhs.id.uuidString)
        }

      return RouteExportDTO(
        route: .init(id: route.id, name: route.name, rtaFSA: route.rtaFSA, isBorrowed: route.isBorrowed),
        stops: stops.map {
          .init(
            id: $0.id,
            routeID: $0.routeID,
            tieOut: $0.tieOut,
            sortIndex: $0.sortIndex,
            kind: $0.kind,
            displayName: $0.displayName,
            officialSiteID: $0.officialSiteID,
            locationText: $0.locationText,
            sharesLocationWith: $0.sharesLocationWith,
            latitude: $0.latitude,
            longitude: $0.longitude,
            notes: $0.notes
          )
        },
        modules: modules.map {
          .init(id: $0.id, stopID: $0.stopID, name: $0.name, sortIndex: $0.sortIndex)
        },
        deliveryPoints: deliveryPoints.map {
          .init(
            id: $0.id,
            stopID: $0.stopID,
            moduleID: $0.moduleID,
            kind: $0.kind,
            label: $0.label,
            isParcelLocker: $0.isParcelLocker,
            status: $0.status,
            notes: $0.notes
          )
        },
        addresses: addresses.map {
          .init(
            id: $0.id,
            civicNumber: $0.civicNumber,
            civicRangeFrom: $0.civicRangeFrom,
            civicRangeTo: $0.civicRangeTo,
            suite: $0.suite,
            street: $0.street,
            occupantName: $0.occupantName,
            doorLatitude: $0.doorLatitude,
            doorLongitude: $0.doorLongitude,
            postalCode: $0.postalCode,
            notes: $0.notes
          )
        },
        tags: tags.map {
          .init(id: $0.id, name: $0.name, isWarning: $0.isWarning)
        },
        deliveryPointAddresses: deliveryPointAddresses.map {
          .init(id: $0.id, deliveryPointID: $0.deliveryPointID, addressID: $0.addressID)
        },
        addressTags: addressTags.map {
          .init(id: $0.id, addressID: $0.addressID, tagID: $0.tagID)
        }
      )
    }
  }

  public static func insert(
    _ dto: RouteExportDTO,
    asBorrowed: Bool,
    into database: any DatabaseWriter
  ) throws -> Route.ID {
    let newRouteID = UUID()

    try database.write { db in
      let stopIDs = try idMap(for: dto.stops.map(\.id))
      let moduleIDs = try idMap(for: dto.modules.map(\.id))
      let deliveryPointIDs = try idMap(for: dto.deliveryPoints.map(\.id))
      let addressIDs = try idMap(for: dto.addresses.map(\.id))
      let tagIDs = try idMap(for: dto.tags.map(\.id))

      try Route.insert {
        Route(id: newRouteID, name: dto.route.name, rtaFSA: dto.route.rtaFSA, isBorrowed: asBorrowed)
      }
      .execute(db)

      for stop in dto.stops {
        guard let stopID = stopIDs[stop.id] else { throw DTOMappingError.malformedGraph }
        try Stop.insert {
          Stop(
            id: stopID,
            routeID: newRouteID,
            tieOut: stop.tieOut,
            sortIndex: stop.sortIndex,
            kind: stop.kind,
            displayName: stop.displayName,
            officialSiteID: stop.officialSiteID,
            locationText: stop.locationText,
            sharesLocationWith: stop.sharesLocationWith,
            latitude: stop.latitude,
            longitude: stop.longitude,
            notes: stop.notes
          )
        }
        .execute(db)
      }

      for module in dto.modules {
        guard
          let moduleID = moduleIDs[module.id],
          let stopID = stopIDs[module.stopID]
        else { throw DTOMappingError.malformedGraph }

        try Module.insert {
          Module(id: moduleID, stopID: stopID, name: module.name, sortIndex: module.sortIndex)
        }
        .execute(db)
      }

      for deliveryPoint in dto.deliveryPoints {
        guard
          let deliveryPointID = deliveryPointIDs[deliveryPoint.id],
          let stopID = stopIDs[deliveryPoint.stopID]
        else { throw DTOMappingError.malformedGraph }

        let moduleID: Module.ID?
        if let oldModuleID = deliveryPoint.moduleID {
          guard let remappedModuleID = moduleIDs[oldModuleID] else {
            throw DTOMappingError.malformedGraph
          }
          moduleID = remappedModuleID
        } else {
          moduleID = nil
        }

        try DeliveryPoint.insert {
          DeliveryPoint(
            id: deliveryPointID,
            stopID: stopID,
            moduleID: moduleID,
            kind: deliveryPoint.kind,
            label: deliveryPoint.label,
            isParcelLocker: deliveryPoint.isParcelLocker,
            status: deliveryPoint.status,
            notes: deliveryPoint.notes
          )
        }
        .execute(db)
      }

      for address in dto.addresses {
        guard let addressID = addressIDs[address.id] else { throw DTOMappingError.malformedGraph }
        try Address.insert {
          Address(
            id: addressID,
            civicNumber: address.civicNumber,
            civicRangeFrom: address.civicRangeFrom,
            civicRangeTo: address.civicRangeTo,
            suite: address.suite,
            street: address.street,
            occupantName: address.occupantName,
            doorLatitude: address.doorLatitude,
            doorLongitude: address.doorLongitude,
            postalCode: address.postalCode,
            notes: address.notes
          )
        }
        .execute(db)
      }

      for tag in dto.tags {
        guard let tagID = tagIDs[tag.id] else { throw DTOMappingError.malformedGraph }
        try Tag.insert {
          Tag(id: tagID, name: tag.name, isWarning: tag.isWarning)
        }
        .execute(db)
      }

      for link in dto.deliveryPointAddresses {
        guard
          let deliveryPointID = deliveryPointIDs[link.deliveryPointID],
          let addressID = addressIDs[link.addressID]
        else { throw DTOMappingError.malformedGraph }

        try DeliveryPointAddress.insert {
          DeliveryPointAddress(id: UUID(), deliveryPointID: deliveryPointID, addressID: addressID)
        }
        .execute(db)
      }

      for link in dto.addressTags {
        guard
          let addressID = addressIDs[link.addressID],
          let tagID = tagIDs[link.tagID]
        else { throw DTOMappingError.malformedGraph }

        try AddressTag.insert {
          AddressTag(id: UUID(), addressID: addressID, tagID: tagID)
        }
        .execute(db)
      }
    }

    return newRouteID
  }

  private static func idMap(for oldIDs: [UUID]) throws -> [UUID: UUID] {
    var mappedIDs: [UUID: UUID] = [:]
    for oldID in oldIDs {
      guard mappedIDs[oldID] == nil else { throw DTOMappingError.malformedGraph }
      mappedIDs[oldID] = UUID()
    }
    return mappedIDs
  }
}

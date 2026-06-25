import Foundation
import SQLiteData
import RouteyModel

public struct SearchService {
  public var database: any DatabaseReader

  public init(database: any DatabaseReader) {
    self.database = database
  }

  public func search(_ query: String) throws -> [SearchHit] {
    try database.read { db in
      let addressIDs = try SearchIndex.match(query, in: db)
      var hits = [SearchHit]()

      for addressID in addressIDs {
        if let hit = try hit(for: addressID, in: db) {
          hits.append(hit)
        }
      }

      return hits
    }
  }

  private func hit(for addressID: UUID, in db: Database) throws -> SearchHit? {
    let pointLinks = try DeliveryPointAddress
      .where { $0.addressID.eq(#bind(addressID)) }
      .fetchAll(db)

    guard
      let address = try Address.find(addressID).fetchOne(db),
      let pointLink = pointLinks.first,
      let deliveryPoint = try DeliveryPoint.find(pointLink.deliveryPointID).fetchOne(db),
      let stop = try Stop.find(deliveryPoint.stopID).fetchOne(db)
    else { return nil }

    let module = try deliveryPoint.moduleID.flatMap { moduleID in
      try Module.find(moduleID).fetchOne(db)
    }

    return SearchHit(
      address: address,
      stopNickname: stop.displayName,
      tieOut: stop.tieOut,
      moduleName: module?.name,
      compartmentLabel: deliveryPoint.label.isEmpty ? nil : deliveryPoint.label,
      sharedCivics: try sharedCivics(for: addressID, deliveryPointID: deliveryPoint.id, in: db),
      tags: try tags(for: addressID, in: db)
    )
  }

  private func sharedCivics(for addressID: UUID, deliveryPointID: UUID, in db: Database) throws -> [Int] {
    let links = try DeliveryPointAddress
      .where { $0.deliveryPointID.eq(#bind(deliveryPointID)) }
      .fetchAll(db)

    var civics = [Int]()
    for link in links where link.addressID != addressID {
      if let civic = try Address.find(link.addressID).fetchOne(db)?.civicNumber {
        civics.append(civic)
      }
    }

    return civics.sorted()
  }

  private func tags(for addressID: UUID, in db: Database) throws -> [SearchTag] {
    let links = try AddressTag
      .where { $0.addressID.eq(#bind(addressID)) }
      .fetchAll(db)

    var tags = [SearchTag]()
    for link in links {
      if let tag = try Tag.find(link.tagID).fetchOne(db) {
        tags.append(SearchTag(id: tag.id, name: tag.name, isWarning: tag.isWarning))
      }
    }

    return tags.sorted { $0.name < $1.name }
  }
}

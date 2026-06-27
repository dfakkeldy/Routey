import Foundation
import Observation
import RouteyModel
import RouteyPersistence
import SQLiteData

@MainActor
@Observable
final class MacProofModel {
  var counts = ProofCounts()
  var routeNames: [String] = []
  var proofStopOrder: [String] = []
  var status = "Starting"
  var isWorking = false
  private(set) var isOpen = false

  @ObservationIgnored private var database: (any DatabaseWriter)?
  @ObservationIgnored private var syncEngine: SyncEngine?

  private static let proofRoutePrefix = "Proof Route"
  private static let proofNote = "Routey sync proof"
  private static let proofTagName = "proof-alert"

  func start() async {
    guard !isOpen else { return }
    await perform("Opening database") {
      let database = try appDatabase()
      let syncEngine = try routeySyncEngine(for: database)
      prepareDependencies {
        $0.defaultDatabase = database
        $0.defaultSyncEngine = syncEngine
      }
      self.database = database
      self.syncEngine = syncEngine
      self.isOpen = true
      try self.refreshSnapshot()
    }
  }

  func refresh() async {
    await perform("Refreshing") {
      try self.refreshSnapshot()
    }
  }

  func seedProofGraph() async {
    await perform("Seeding proof data") {
      let database = try self.openDatabase()
      let routeID = UUID()
      let firstStopID = UUID()
      let secondStopID = UUID()
      let moduleID = UUID()
      let deliveryPointID = UUID()
      let addressID = UUID()
      let suffix = UUID().uuidString.prefix(8).lowercased()

      try database.write { db in
        try Route.insert {
          Route(id: routeID, name: "\(Self.proofRoutePrefix) \(suffix)")
        }
        .execute(db)

        try Stop.insert {
          Stop(
            id: firstStopID,
            routeID: routeID,
            tieOut: "A",
            sortIndex: 0,
            displayName: "Proof Stop A",
            notes: Self.proofNote
          )
        }
        .execute(db)

        try Stop.insert {
          Stop(
            id: secondStopID,
            routeID: routeID,
            tieOut: "B",
            sortIndex: 1,
            displayName: "Proof Stop B",
            notes: Self.proofNote
          )
        }
        .execute(db)

        try Module.insert {
          Module(id: moduleID, stopID: firstStopID, name: "Proof Module", sortIndex: 0)
        }
        .execute(db)

        try DeliveryPoint.insert {
          DeliveryPoint(
            id: deliveryPointID,
            stopID: firstStopID,
            moduleID: moduleID,
            kind: "compartment",
            label: "Proof Slot",
            notes: Self.proofNote
          )
        }
        .execute(db)

        try Address.insert {
          Address(
            id: addressID,
            street: "Invented Way",
            occupantName: "Placeholder Contact",
            notes: Self.proofNote
          )
        }
        .execute(db)

        try DeliveryPointAddress.insert {
          DeliveryPointAddress(deliveryPointID: deliveryPointID, addressID: addressID)
        }
        .execute(db)

        let existingTag = try Tag.all.fetchAll(db).first { $0.name == Self.proofTagName }
        let tagID: Tag.ID
        if let existingTag {
          tagID = existingTag.id
        } else {
          tagID = UUID()
          try Tag.insert {
            Tag(id: tagID, name: Self.proofTagName, isWarning: true)
          }
          .execute(db)
        }

        try AddressTag.insert {
          AddressTag(addressID: addressID, tagID: tagID)
        }
        .execute(db)
      }

      try self.refreshSnapshot()
    }
  }

  func moveFirstProofStop() async {
    await perform("Moving proof stop") {
      let database = try self.openDatabase()
      try database.write { db in
        let routes = try Route.all.fetchAll(db)
          .filter { $0.name.hasPrefix(Self.proofRoutePrefix) }
          .sorted { $0.name < $1.name }
        guard let route = routes.last else {
          throw MacProofError.noProofRoute
        }

        let stops = try Stop
          .where { $0.routeID.eq(#bind(route.id)) }
          .order { $0.sortIndex }
          .fetchAll(db)
        guard let firstStop = stops.first, stops.count > 1 else {
          throw MacProofError.notEnoughStops
        }

        let newIndex = (stops.last?.sortIndex ?? firstStop.sortIndex) + 1
        try Stop.find(firstStop.id)
          .update {
            $0.sortIndex = #bind(newIndex)
            $0.notes = #bind(Self.proofNote)
          }
          .execute(db)
      }

      try self.refreshSnapshot()
    }
  }

  func deleteProofData() async {
    await perform("Deleting proof data") {
      let database = try self.openDatabase()
      try database.write { db in
        let routes = try Route.all.fetchAll(db)
        for route in routes where route.name.hasPrefix(Self.proofRoutePrefix) {
          try Route.find(route.id)
            .delete()
            .execute(db)
        }

        let addresses = try Address.all.fetchAll(db)
        for address in addresses where address.notes == Self.proofNote {
          try Address.find(address.id)
            .delete()
            .execute(db)
        }

        let tags = try Tag.all.fetchAll(db)
        for tag in tags where tag.name == Self.proofTagName {
          try Tag.find(tag.id)
            .delete()
            .execute(db)
        }
      }

      try self.refreshSnapshot()
    }
  }

  func pushChanges() async {
    await perform("Pushing changes") {
      try await self.openSyncEngine().sendChanges()
      try self.refreshSnapshot()
    }
  }

  func pullChanges() async {
    await perform("Pulling changes") {
      try await self.openSyncEngine().fetchChanges()
      try self.refreshSnapshot()
    }
  }

  func syncNow() async {
    await perform("Syncing") {
      try await self.openSyncEngine().syncChanges()
      try self.refreshSnapshot()
    }
  }

  private func perform(_ title: String, operation: () async throws -> Void) async {
    guard !isWorking else { return }
    isWorking = true
    status = title
    defer { isWorking = false }

    do {
      try await operation()
      status = "\(title) complete"
    } catch {
      status = error.localizedDescription
    }
  }

  private func refreshSnapshot() throws {
    let database = try openDatabase()
    let snapshot = try database.read { db in
      let routes = try Route.all.order { $0.name }.fetchAll(db)
      let proofRoute = routes.filter { $0.name.hasPrefix(Self.proofRoutePrefix) }.last
      let stops: [Stop]
      if let proofRoute {
        stops = try Stop
          .where { $0.routeID.eq(#bind(proofRoute.id)) }
          .order { $0.sortIndex }
          .fetchAll(db)
      } else {
        stops = []
      }

      return ProofSnapshot(
        counts: ProofCounts(
          routes: try Route.all.fetchAll(db).count,
          stops: try Stop.all.fetchAll(db).count,
          modules: try Module.all.fetchAll(db).count,
          deliveryPoints: try DeliveryPoint.all.fetchAll(db).count,
          addresses: try Address.all.fetchAll(db).count,
          tags: try Tag.all.fetchAll(db).count
        ),
        routeNames: routes.map(\.name),
        proofStopOrder: stops.map(\.displayName)
      )
    }

    counts = snapshot.counts
    routeNames = snapshot.routeNames
    proofStopOrder = snapshot.proofStopOrder
  }

  private func openDatabase() throws -> any DatabaseWriter {
    guard let database else { throw MacProofError.databaseClosed }
    return database
  }

  private func openSyncEngine() throws -> SyncEngine {
    guard let syncEngine else { throw MacProofError.syncEngineClosed }
    return syncEngine
  }
}

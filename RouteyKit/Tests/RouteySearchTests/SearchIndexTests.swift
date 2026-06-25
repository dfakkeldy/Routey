import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyPersistence
@testable import RouteySearch

@Suite struct SearchIndexTests {
  private func dbWithAddresses() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)

    try database.write { db in
      try SearchIndex.install(db)

      try Address.insert {
        Address(id: UUID(), civicNumber: 1284, street: "Concession Rd 6")
      }
      .execute(db)

      try Address.insert {
        Address(id: UUID(), civicNumber: 88, street: "Maple Side Rd", occupantName: "Sara")
      }
      .execute(db)

      try SearchIndex.rebuild(from: db)
    }

    return database
  }

  @Test func prefixMatchOnCivicNumber() throws {
    let database = try dbWithAddresses()

    let hits = try database.read { db in
      try SearchIndex.match("128", in: db)
    }

    #expect(hits.count == 1)
  }

  @Test func matchOnStreetToken() throws {
    let database = try dbWithAddresses()

    let hits = try database.read { db in
      try SearchIndex.match("maple", in: db)
    }

    #expect(hits.count == 1)
  }

  @Test func matchOnOccupantName() throws {
    let database = try dbWithAddresses()

    let hits = try database.read { db in
      try SearchIndex.match("sar", in: db)
    }

    #expect(hits.count == 1)
  }

  @Test func noMatchReturnsEmpty() throws {
    let database = try dbWithAddresses()

    let hits = try database.read { db in
      try SearchIndex.match("99999", in: db)
    }

    #expect(hits.isEmpty)
  }
}

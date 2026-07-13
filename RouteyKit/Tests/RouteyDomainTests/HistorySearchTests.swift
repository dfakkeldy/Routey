import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence
@testable import RouteySearch

@Suite struct HistorySearchTests {
  private struct HistoryFixture {
    var dogRecordID: DeliveryRecord.ID
    var photoRecordID: DeliveryRecord.ID
    var cardedRecordID: DeliveryRecord.ID
    var queryNewestRecordID: DeliveryRecord.ID
    var queryOlderRecordID: DeliveryRecord.ID
  }

  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  private func seedHistory(in database: DatabaseQueue) throws -> HistoryFixture {
    let routeID = UUID()
    let runID = UUID()
    let dogAddressID = UUID()
    let photoAddressID = UUID()
    let cardedAddressID = UUID()
    let tagID = UUID()
    let dogRecordID = UUID()
    let photoRecordID = UUID()
    let cardedRecordID = UUID()
    let queryNewestRecordID = UUID()
    let queryOlderRecordID = UUID()

    try database.write { db in
      try SearchIndex.install(db)
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try TodaysRun.insert {
        TodaysRun(
          id: runID,
          routeID: routeID,
          serviceDate: "2026-06-22",
          createdAt: Date(timeIntervalSince1970: 1_782_000_000)
        )
      }
      .execute(db)

      try Address.insert {
        Address(id: dogAddressID, civicNumber: 2400, street: "Example Lane")
      }
      .execute(db)
      try Address.insert {
        Address(id: photoAddressID, civicNumber: 2402, street: "Sample Court")
      }
      .execute(db)
      try Address.insert {
        Address(id: cardedAddressID, civicNumber: 2404, street: "Placeholder Road")
      }
      .execute(db)

      try Tag.insert { Tag(id: tagID, name: "dog", isWarning: true) }.execute(db)
      try AddressTag.insert { AddressTag(addressID: dogAddressID, tagID: tagID) }.execute(db)

      try DeliveryRecord.insert {
        DeliveryRecord(
          id: dogRecordID,
          runID: runID,
          addressID: dogAddressID,
          outcome: "mailbox",
          loggedAt: Date(timeIntervalSince1970: 1_782_003_600)
        )
      }
      .execute(db)
      try DeliveryRecord.insert {
        DeliveryRecord(
          id: photoRecordID,
          runID: runID,
          addressID: photoAddressID,
          outcome: "safedrop",
          loggedAt: Date(timeIntervalSince1970: 1_782_007_200),
          photoPath: "proofs/sample-photo.jpg"
        )
      }
      .execute(db)
      try DeliveryRecord.insert {
        DeliveryRecord(
          id: cardedRecordID,
          runID: runID,
          addressID: cardedAddressID,
          outcome: "notHomeCarded",
          loggedAt: Date(timeIntervalSince1970: 1_782_010_800)
        )
      }
      .execute(db)
      try DeliveryRecord.insert {
        DeliveryRecord(
          id: queryOlderRecordID,
          runID: runID,
          addressID: dogAddressID,
          outcome: "mailbox",
          loggedAt: Date(timeIntervalSince1970: 1_782_014_400)
        )
      }
      .execute(db)
      try DeliveryRecord.insert {
        DeliveryRecord(
          id: queryNewestRecordID,
          runID: runID,
          addressID: dogAddressID,
          outcome: "safedrop",
          loggedAt: Date(timeIntervalSince1970: 1_782_018_000)
        )
      }
      .execute(db)

      try SearchIndex.rebuild(from: db)
    }

    return HistoryFixture(
      dogRecordID: dogRecordID,
      photoRecordID: photoRecordID,
      cardedRecordID: cardedRecordID,
      queryNewestRecordID: queryNewestRecordID,
      queryOlderRecordID: queryOlderRecordID
    )
  }

  @Test func recordsMatchingAppliesOutcomePhotoTagAndDateFilters() throws {
    let database = try freshDB()
    let fixture = try seedHistory(in: database)

    let safedrops = try History.records(
      matching: History.HistoryFilter(outcome: "safedrop"),
      in: database
    )
    let recordsWithPhotos = try History.records(
      matching: History.HistoryFilter(hasPhoto: true),
      in: database
    )
    let recordsWithoutPhotos = try History.records(
      matching: History.HistoryFilter(hasPhoto: false),
      in: database
    )
    let dogRecords = try History.records(
      matching: History.HistoryFilter(tagName: "dog"),
      in: database
    )
    let recordsInDateRange = try History.records(
      matching: History.HistoryFilter(
        dateFrom: Date(timeIntervalSince1970: 1_782_007_200),
        dateTo: Date(timeIntervalSince1970: 1_782_014_400)
      ),
      in: database
    )

    #expect(safedrops.map(\.id) == [fixture.queryNewestRecordID, fixture.photoRecordID])
    #expect(recordsWithPhotos.map(\.id) == [fixture.photoRecordID])
    #expect(recordsWithoutPhotos.map(\.id) == [
      fixture.queryNewestRecordID,
      fixture.queryOlderRecordID,
      fixture.cardedRecordID,
      fixture.dogRecordID,
    ])
    #expect(dogRecords.map(\.id) == [
      fixture.queryNewestRecordID,
      fixture.queryOlderRecordID,
      fixture.dogRecordID,
    ])
    #expect(recordsInDateRange.map(\.id) == [
      fixture.queryOlderRecordID,
      fixture.cardedRecordID,
      fixture.photoRecordID,
    ])
  }

  @Test func recordsMatchingReturnsMostRecentRecordsFirst() throws {
    let database = try freshDB()
    let fixture = try seedHistory(in: database)

    let records = try History.records(matching: History.HistoryFilter(), in: database)

    #expect(records.map(\.id) == [
      fixture.queryNewestRecordID,
      fixture.queryOlderRecordID,
      fixture.cardedRecordID,
      fixture.photoRecordID,
      fixture.dogRecordID,
    ])
  }

  @Test func recordsForAddressQueryUsesSearchIndexAndReturnsMostRecentFirst() throws {
    let database = try freshDB()
    let fixture = try seedHistory(in: database)

    let records = try History.records(forAddressQuery: "2400 exa", in: database)

    #expect(records.map(\.id) == [
      fixture.queryNewestRecordID,
      fixture.queryOlderRecordID,
      fixture.dogRecordID,
    ])
  }
}

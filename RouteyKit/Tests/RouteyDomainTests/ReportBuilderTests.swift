import Foundation
import SQLiteData
import Testing
import RouteyModel
@testable import RouteyDomain
@testable import RouteyPersistence

@Suite struct ReportBuilderTests {
  private struct ReportFixture {
    var routeID: Route.ID
  }

  private func freshDB() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try Schema.migrator.migrate(database)
    return database
  }

  private func seedReportRoute(in database: DatabaseQueue) throws -> ReportFixture {
    let routeID = UUID()
    let siteStopID = UUID()
    let roadStopID = UUID()
    let moduleID = UUID()
    let slotTwoID = UUID()
    let slotThreeID = UUID()
    let roadBoxID = UUID()
    let slotTwoAddressID = UUID()
    let sharedAddressOneID = UUID()
    let sharedAddressTwoID = UUID()
    let roadAddressID = UUID()
    let alertTagID = UUID()
    let noFlyersTagID = UUID()
    let runID = UUID()

    try database.write { db in
      try Route.insert { Route(id: routeID, name: "Sample Route") }.execute(db)
      try Stop.insert {
        Stop(
          id: roadStopID,
          routeID: routeID,
          tieOut: "B",
          sortIndex: 20,
          kind: "pointOfCall",
          displayName: "Road Box"
        )
      }
      .execute(db)
      try Stop.insert {
        Stop(
          id: siteStopID,
          routeID: routeID,
          tieOut: "A",
          sortIndex: 10,
          kind: "cmbSite",
          displayName: "Shared Compartment Site"
        )
      }
      .execute(db)
      try Module.insert {
        Module(id: moduleID, stopID: siteStopID, name: "Module Blue", sortIndex: 0)
      }
      .execute(db)
      try DeliveryPoint.insert {
        DeliveryPoint(
          id: slotTwoID,
          stopID: siteStopID,
          moduleID: moduleID,
          kind: "compartment",
          label: "Slot 2"
        )
      }
      .execute(db)
      try DeliveryPoint.insert {
        DeliveryPoint(
          id: slotThreeID,
          stopID: siteStopID,
          moduleID: moduleID,
          kind: "compartment",
          label: "Slot 3"
        )
      }
      .execute(db)
      try DeliveryPoint.insert {
        DeliveryPoint(
          id: roadBoxID,
          stopID: roadStopID,
          kind: "roadsideBox",
          label: "Roadside Box"
        )
      }
      .execute(db)

      try Address.insert {
        Address(id: slotTwoAddressID, civicNumber: 101, street: "Sample Lane")
      }
      .execute(db)
      try Address.insert {
        Address(id: sharedAddressOneID, civicNumber: 103, street: "Sample Lane")
      }
      .execute(db)
      try Address.insert {
        Address(id: sharedAddressTwoID, civicNumber: 105, street: "Sample Lane")
      }
      .execute(db)
      try Address.insert {
        Address(id: roadAddressID, civicNumber: 205, street: "Example Road")
      }
      .execute(db)

      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: slotTwoID, addressID: slotTwoAddressID)
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: slotThreeID, addressID: sharedAddressOneID)
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: slotThreeID, addressID: sharedAddressTwoID)
      }
      .execute(db)
      try DeliveryPointAddress.insert {
        DeliveryPointAddress(deliveryPointID: roadBoxID, addressID: roadAddressID)
      }
      .execute(db)

      try Tag.insert { Tag(id: alertTagID, name: "alert", isWarning: true) }.execute(db)
      try Tag.insert { Tag(id: noFlyersTagID, name: "no-flyers") }.execute(db)
      try AddressTag.insert {
        AddressTag(addressID: slotTwoAddressID, tagID: noFlyersTagID)
      }
      .execute(db)
      try AddressTag.insert {
        AddressTag(addressID: slotTwoAddressID, tagID: alertTagID)
      }
      .execute(db)

      try TodaysRun.insert {
        TodaysRun(
          id: runID,
          routeID: routeID,
          serviceDate: "2026-06-23",
          createdAt: Date(timeIntervalSince1970: 1_782_172_800)
        )
      }
      .execute(db)
      try DeliveryRecord.insert {
        DeliveryRecord(
          runID: runID,
          addressID: roadAddressID,
          outcome: "mailbox",
          loggedAt: Date(timeIntervalSince1970: 1_782_257_400)
        )
      }
      .execute(db)
      try DeliveryRecord.insert {
        DeliveryRecord(
          runID: runID,
          addressID: sharedAddressOneID,
          outcome: "mailbox",
          loggedAt: Date(timeIntervalSince1970: 1_782_261_000)
        )
      }
      .execute(db)
    }

    return ReportFixture(routeID: routeID)
  }

  @Test func tieOutSheetUsesRouteOrderLocatorAndSortedTags() throws {
    let database = try freshDB()
    let fixture = try seedReportRoute(in: database)

    let report = try ReportBuilder.tieOutSheet(routeID: fixture.routeID, in: database)

    #expect(report.title == "Tie-out Sheet")
    #expect(report.columns == ["Tie-out", "Civic", "Street", "Site/Compartment", "Tags"])
    #expect(report.rows == [
      ["A", "101", "Sample Lane", "Shared Compartment Site / Module Blue / Slot 2", "alert, no-flyers"],
      ["A", "103, 105", "Sample Lane", "Shared Compartment Site / Module Blue / Slot 3", ""],
      ["B", "205", "Example Road", "Road Box / Roadside Box", ""],
    ])
  }

  @Test func filteredListCanFilterByTagOrServiceDate() throws {
    let database = try freshDB()
    let fixture = try seedReportRoute(in: database)

    let tagged = try ReportBuilder.filteredList(
      routeID: fixture.routeID,
      tagName: "no-flyers",
      deliveredOn: nil,
      in: database
    )
    let deliveredOnDate = try #require(Calendar.current.date(
      from: DateComponents(year: 2026, month: 6, day: 23, hour: 12)
    ))
    let deliveredOnServiceDate = try ReportBuilder.filteredList(
      routeID: fixture.routeID,
      tagName: nil,
      deliveredOn: deliveredOnDate,
      in: database
    )

    #expect(tagged.columns == ["Tie-out", "Civic", "Street", "Site/Compartment", "Tags"])
    #expect(tagged.rows == [
      ["A", "101", "Sample Lane", "Shared Compartment Site / Module Blue / Slot 2", "alert, no-flyers"],
    ])
    #expect(deliveredOnServiceDate.rows == [
      ["A", "103", "Sample Lane", "Shared Compartment Site / Module Blue / Slot 3", ""],
      ["B", "205", "Example Road", "Road Box / Roadside Box", ""],
    ])
  }

  @Test func caseStripsListCivicsAndTieOutsPerSlotInCaseOrder() throws {
    let database = try freshDB()
    let fixture = try seedReportRoute(in: database)

    let report = try ReportBuilder.caseStrips(routeID: fixture.routeID, in: database)

    #expect(report.title == "Case Strips")
    #expect(report.columns == ["Civic", "Tie-out", "Slot"])
    #expect(report.rows == [
      ["101", "A", "Shared Compartment Site / Module Blue / Slot 2"],
      ["103, 105", "A", "Shared Compartment Site / Module Blue / Slot 3"],
      ["205", "B", "Road Box / Roadside Box"],
    ])
  }
}

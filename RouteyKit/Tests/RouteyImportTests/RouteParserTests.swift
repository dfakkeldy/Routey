import Testing
@testable import RouteyImport

@Suite struct RouteParserTests {
  @Test func parsesFreeformCivicAndStreet() {
    let result = RouteParser.parse("10100 County Rd 12\n38 Northgate Rd\n")

    #expect(result.skipped.isEmpty)
    #expect(result.stops.count == 2)
    #expect(
      result.stops[0] == ParsedStop(
        civicNumber: 10100,
        street: "County Rd 12",
        sourceLine: 1
      )
    )
    #expect(result.stops[1].civicNumber == 38)
    #expect(result.stops[1].street == "Northgate Rd")
  }

  @Test func ignoresBlankLinesAndTracksLineNumbers() {
    let result = RouteParser.parse("\n\n10100 County Rd 12\n\n")

    #expect(result.stops.count == 1)
    #expect(result.stops[0].sourceLine == 3)
  }

  @Test func skipsRowsWithNeitherCivicNorStreet() {
    let result = RouteParser.parse("---\n10100 County Rd 12\n")

    #expect(result.stops.count == 1)
    #expect(result.skipped.count == 1)
    #expect(result.skipped[0].line == 1)
    #expect(result.skipped[0].reason == "no civic number or street")
  }

  @Test func parsesCSVWithHeaders() {
    let csv = """
      tieOut,civic,street,occupant,notes
      1,10100,County Rd 12,,
      20A,3400,County Rd 12,Alex,by the barn
      """

    let result = RouteParser.parse(csv)

    #expect(result.stops.count == 2)
    #expect(
      result.stops[0] == ParsedStop(
        tieOut: "1",
        civicNumber: 10100,
        street: "County Rd 12",
        sourceLine: 2
      )
    )
    #expect(result.stops[1].tieOut == "20A")
    #expect(result.stops[1].occupantName == "Alex")
    #expect(result.stops[1].notes == "by the barn")
  }

  @Test func streetOnlyRowIsKept() {
    let result = RouteParser.parse("Harbour Rd\n")

    #expect(result.stops.count == 1)
    #expect(result.stops[0].civicNumber == nil)
    #expect(result.stops[0].street == "Harbour Rd")
  }
}

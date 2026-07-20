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
      tieOut,civic,street,occupant,postalCode,notes
      1,10100,County Rd 12,,A1A 1A1,
      20A,3400,County Rd 12,Alex,A1A 1A1,by the barn
      """

    let result = RouteParser.parse(csv)

    #expect(result.stops.count == 2)
    #expect(
      result.stops[0] == ParsedStop(
        tieOut: "1",
        civicNumber: 10100,
        street: "County Rd 12",
        postalCode: "A1A 1A1",
        sourceLine: 2
      )
    )
    #expect(result.stops[1].tieOut == "20A")
    #expect(result.stops[1].occupantName == "Alex")
    #expect(result.stops[1].postalCode == "A1A 1A1")
    #expect(result.stops[1].notes == "by the barn")
  }

  @Test func parsesCSVHeadersWithCommonSeparators() {
    let csv = """
      tie_out,civic,street,postal code
      1,10100,County Rd 12,A1A 1A1
      """

    let result = RouteParser.parse(csv)

    #expect(result.stops.count == 1)
    #expect(result.stops[0].tieOut == "1")
    #expect(result.stops[0].postalCode == "A1A 1A1")
  }

  @Test func parsesSharedSiteLocationAndTagsFromCSV() {
    let csv = """
      civic,street,site,module,compartment,tags,warnings
      10100,County Rd 12,Community Boxes,5,7,no-flyers;side-door,dog
      """

    let result = RouteParser.parse(csv)

    #expect(result.stops.count == 1)
    #expect(result.stops[0].siteName == "Community Boxes")
    #expect(result.stops[0].moduleName == "5")
    #expect(result.stops[0].compartmentLabel == "7")
    #expect(result.stops[0].tags == ["no-flyers", "side-door"])
    #expect(result.stops[0].warningTags == ["dog"])
  }

  @Test func streetOnlyRowIsKept() {
    let result = RouteParser.parse("Harbour Rd\n")

    #expect(result.stops.count == 1)
    #expect(result.stops[0].civicNumber == nil)
    #expect(result.stops[0].street == "Harbour Rd")
  }
}

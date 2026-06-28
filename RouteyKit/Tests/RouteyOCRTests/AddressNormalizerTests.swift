import Testing
@testable import RouteyOCR

@Suite struct AddressNormalizerTests {
  @Test func normalizesCivicStreetUnitDirectionOccupantAndPostalCode() {
    let components = AddressNormalizer.normalize(
      """
      Rowan Vale
      Unit 5
      123 Rue Principale O
      A1A 1X0
      """
    )

    #expect(components.civicNumber == 123)
    #expect(components.unit == "5")
    #expect(components.streetTokens == ["street", "principale", "west"])
    #expect(components.occupant == "rowan vale")
    #expect(components.postalCode == "a1a1x0")
  }

  @Test func normalizesRuralRouteWithoutCivic() {
    let components = AddressNormalizer.normalize("Morgan Field\nRR 2 Riverbend A1A 1X0")

    #expect(components.civicNumber == nil)
    #expect(components.routeNumber == "rural route 2")
    #expect(components.streetTokens == ["riverbend"])
    #expect(components.occupant == "morgan field")
    #expect(components.postalCode == "a1a1x0")
  }

  @Test func normalizesConcessionAndHighwayStyleForms() {
    let concession = AddressNormalizer.normalize("1284 Conc Rd 6")
    let highway = AddressNormalizer.normalize("Lot 7 Hwy 19")

    #expect(concession.civicNumber == 1284)
    #expect(concession.routeNumber == "concession 6")
    #expect(concession.streetTokens == ["concession", "road", "6"])

    #expect(highway.civicNumber == nil)
    #expect(highway.routeNumber == "highway 19 lot 7")
    #expect(highway.streetTokens == ["lot", "7", "highway", "19"])
  }

  @Test func damerauLevenshteinCountsAdjacentTranspositionAsOneEdit() {
    #expect(AddressNormalizer.damerauLevenshtein("recieve", "receive") == 1)
    #expect(AddressNormalizer.damerauLevenshtein("form", "from") == 1)
  }
}

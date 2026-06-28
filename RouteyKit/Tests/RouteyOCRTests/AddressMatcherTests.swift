import Foundation
import Testing
import RouteyModel
@testable import RouteyOCR

@Suite struct AddressMatcherTests {
  @Test func exactCivicAndStreetAutoAccepts() {
    let addressID = UUID()
    let components = AddressNormalizer.normalize("41 Maple Rd")
    let ranked = AddressMatcher.rank(
      components,
      against: [
        AddressCandidate(id: addressID, civicNumber: 41, street: "Maple Road")
      ]
    )

    #expect(AddressMatcher.band(ranked, for: components) == .autoAccept(addressID))
  }

  @Test func confidentCivicMismatchIsDisqualified() {
    let correctID = UUID()
    let mismatchedID = UUID()
    let components = AddressNormalizer.normalize("12 Northgate St")
    let ranked = AddressMatcher.rank(
      components,
      against: [
        AddressCandidate(id: mismatchedID, civicNumber: 21, street: "Northgate Street"),
        AddressCandidate(id: correctID, civicNumber: 12, street: "Northgate Street"),
      ]
    )

    #expect(ranked.first?.id == correctID)
    #expect(ranked.first(where: { $0.id == mismatchedID })?.score == 0)
  }

  @Test func occupantBreaksSharedCivicTie() {
    let matchedID = UUID()
    let otherID = UUID()
    let components = AddressNormalizer.normalize("Alex Reed\n31 Elm St")
    let ranked = AddressMatcher.rank(
      components,
      against: [
        AddressCandidate(id: otherID, civicNumber: 31, street: "Elm Street", occupantName: "Sam Reed"),
        AddressCandidate(id: matchedID, civicNumber: 31, street: "Elm Street", occupantName: "Alex Reed"),
      ]
    )

    #expect(ranked.first?.id == matchedID)
    #expect(AddressMatcher.band(ranked, for: components) == .autoAccept(matchedID))
  }

  @Test func nearMissStreetRanksForReview() {
    let candidateID = UUID()
    let components = AddressNormalizer.normalize("72 Pine Rod")
    let ranked = AddressMatcher.rank(
      components,
      against: [
        AddressCandidate(id: candidateID, civicNumber: 72, street: "Pine Road")
      ]
    )

    #expect(ranked.first?.id == candidateID)
    #expect(ranked.first?.score ?? 0 > 0.70)
    #expect(AddressMatcher.band(ranked, for: components).isReview)
  }

  @Test func noPlausibleCandidateReturnsNoMatch() {
    let components = AddressNormalizer.normalize("501 Birch Lane")
    let ranked = AddressMatcher.rank(
      components,
      against: [
        AddressCandidate(civicNumber: 88, street: "Cedar Street")
      ]
    )

    #expect(AddressMatcher.band(ranked, for: components) == .noMatch)
  }

  @Test func occupantOnlyEvidenceCannotAutoAcceptNoCivicCandidate() {
    let candidateID = UUID()
    let components = AddressNormalizer.normalize("Alex Reed")
    let ranked = AddressMatcher.rank(
      components,
      against: [
        AddressCandidate(id: candidateID, street: "Rural Route 2", occupantName: "Alex Reed")
      ]
    )

    #expect(AddressMatcher.band(ranked, for: components) == .noMatch)
  }

  @Test func unitBreaksSharedCivicTie() {
    let matchedID = UUID()
    let otherID = UUID()
    let components = AddressNormalizer.normalize("Unit 2\n31 Elm St")
    let ranked = AddressMatcher.rank(
      components,
      against: [
        AddressCandidate(id: otherID, civicNumber: 31, suite: "1", street: "Elm Street"),
        AddressCandidate(id: matchedID, civicNumber: 31, suite: "2", street: "Elm Street"),
      ]
    )

    #expect(ranked.first?.id == matchedID)
    #expect(AddressMatcher.band(ranked, for: components) == .autoAccept(matchedID))
  }

  @Test func addressCandidatePreservesModelSuite() {
    let address = Address(civicNumber: 31, suite: "2", street: "Elm Street")
    let candidate = AddressCandidate(address)

    #expect(candidate.suite == "2")
  }

  @Test func conflictingLotNumberIsDisqualifiedEvenWhenHighwayNumberMatches() {
    let matchedID = UUID()
    let conflictingID = UUID()
    let components = AddressNormalizer.normalize("Lot 7 Hwy 19")
    let ranked = AddressMatcher.rank(
      components,
      against: [
        AddressCandidate(id: conflictingID, street: "Lot 8 Highway 19"),
        AddressCandidate(id: matchedID, street: "Lot 7 Highway 19"),
      ]
    )

    #expect(ranked.first?.id == matchedID)
    #expect(ranked.first(where: { $0.id == conflictingID })?.score == 0)
  }
}

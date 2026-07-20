import Foundation
import RouteyDomain
import RouteyModel
import RouteyOCR
import Testing
@testable import Routey

@MainActor
@Suite struct SnapViewModelTests {
  @Test func candidateCarriesCaseLocatorAndWarningsIntoConfirmation() {
    let context = RouteAddressContext(
      address: Address(civicNumber: 101, street: "Sample Road"),
      siteName: "Community Boxes",
      moduleName: "5",
      compartmentLabel: "7",
      driveOrder: "10",
      tagNames: ["dog", "no-flyers"],
      warningTagNames: ["dog"]
    )

    let candidate = SnapViewModel.candidate(from: context)

    #expect(candidate.locator == "Community Boxes · Module 5 · Compartment 7 · Drive 10")
    #expect(candidate.tagNames == ["dog", "no-flyers"])
    #expect(candidate.warningTagNames == ["dog"])
    #expect(candidate.hasWarning)
    #expect(
      SnapViewModel.confirmationMessage(for: candidate)
        == "Community Boxes · Module 5 · Compartment 7 · Drive 10\nWarning: dog\nPreference: no-flyers"
    )
  }
}

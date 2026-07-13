import Foundation
import Testing
import RouteyDomain
import RouteyModel
@testable import Routey

@Suite struct RunRouteSelectionTests {
  @Test func defaultsToARealRouteBeforeParcelPile() {
    let parcelPile = Route(name: TemporaryRouteBuilder.routeName)
    let sampleRoute = Route(name: "Sample Route")

    #expect(
      RunRouteSelection.preferredRouteID(in: [parcelPile, sampleRoute], current: nil)
        == sampleRoute.id
    )
  }

  @Test func preservesAValidExplicitSelection() {
    let parcelPile = Route(name: TemporaryRouteBuilder.routeName)
    let sampleRoute = Route(name: "Sample Route")

    #expect(
      RunRouteSelection.preferredRouteID(
        in: [parcelPile, sampleRoute],
        current: parcelPile.id
      ) == parcelPile.id
    )
  }

  @Test func fallsBackWhenTheSelectedRouteDisappears() {
    let sampleRoute = Route(name: "Sample Route")

    #expect(
      RunRouteSelection.preferredRouteID(in: [sampleRoute], current: UUID())
        == sampleRoute.id
    )
  }

  @Test func serviceDateParticipatesInRunLoadIdentity() {
    let routeID = UUID()

    #expect(
      RunLoadContext(routeID: routeID, serviceDate: "2026-07-13")
        != RunLoadContext(routeID: routeID, serviceDate: "2026-07-14")
    )
  }
}

import Foundation
import Testing
@testable import RouteyDomain

@Suite struct ServiceDateTests {
  @Test func localDateUsesTheDeviceTimeZoneInsteadOfGMT() throws {
    let date = try Date("2026-07-14T01:00:00Z", strategy: .iso8601)
    let halifax = try #require(TimeZone(identifier: "America/Halifax"))
    let gmt = try #require(TimeZone(secondsFromGMT: 0))

    #expect(ServiceDate.local(for: date, timeZone: halifax) == "2026-07-13")
    #expect(ServiceDate.local(for: date, timeZone: gmt) == "2026-07-14")
  }
}

import Testing
@testable import Routey

struct RouteyTests {
  @Test func routeyDatabaseBootstrapLoads() throws {
    _ = try routeyDatabase()
    #expect(true)
  }
}

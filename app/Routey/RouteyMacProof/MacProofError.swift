import Foundation

enum MacProofError: LocalizedError {
  case databaseClosed
  case syncEngineClosed
  case noProofRoute
  case notEnoughStops

  var errorDescription: String? {
    switch self {
    case .databaseClosed:
      "The proof database is not open."
    case .syncEngineClosed:
      "The proof sync engine is not open."
    case .noProofRoute:
      "Seed a proof route first."
    case .notEnoughStops:
      "The latest proof route needs at least two stops."
    }
  }
}

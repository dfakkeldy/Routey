import Foundation
import Observation
import RouteyDomain
import RouteyModel
import RouteyOCR
import SQLiteData

@MainActor
@Observable
final class SnapViewModel {
  enum Phase: Equatable {
    case capturing
    case reading
    case result(SnapMatchResult)
    case added(signatureCount: Int)
    case failed(String)
  }

  private(set) var phase: Phase = .capturing
  let route: Route

  private let database: any DatabaseWriter
  private var lastAddedParcelID: UUID?

  init(route: Route, database: any DatabaseWriter) {
    self.route = route
    self.database = database
  }

  func handleCapturedImage(_ data: Data) async {
    phase = .reading
    do {
      let addresses = try await database.read { db in
        try Address.order { $0.street }.fetchAll(db)
      }
      let candidates = addresses.map(AddressCandidate.init)
      let words = Self.customWords(from: addresses)
      let reader = VisionLabelReader(imageData: data, customWords: words)
      let pipeline = SnapPipeline(reader: reader) { _ in candidates }
      let result = try await pipeline.process()
      phase = .result(result)
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  func accept(addressID: UUID?) async {
    guard case .result(let result) = phase else { return }
    do {
      let input = SnapToAdd.parcelInputs(from: result, addressID: addressID)
      let serviceDate = Self.serviceDate(for: .now)
      let runID = try RunGeneration.generate(
        routeID: route.id, serviceDate: serviceDate, now: .now, into: database
      )
      let parcelID = try RunOperations.addParcel(
        runID: runID,
        addressID: input.addressID,
        source: input.source,
        requiresSignature: input.requiresSignature,
        isCustoms: input.isCustoms,
        toDoor: input.toDoor,
        labelSnapshot: input.labelSnapshot,
        trackingCode: input.trackingCode,
        trackingSymbology: input.trackingSymbology,
        in: database
      )
      lastAddedParcelID = parcelID
      let count = try RunOperations.signatureCount(runID: runID, in: database)
      phase = .added(signatureCount: count)
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  func undoLastAdd() async {
    guard let parcelID = lastAddedParcelID else { return }
    do {
      try RunOperations.removeParcel(parcelID, in: database)
      lastAddedParcelID = nil
      phase = .capturing
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  func reset() {
    phase = .capturing
  }

  static func customWords(from addresses: [Address]) -> [String] {
    let streetWords = addresses.flatMap { $0.street.split(separator: " ").map(String.init) }
    let keywords = ["RR", "CONC", "HWY", "LOT", "SS", "PO", "BOX"]
    return Array(Set(streetWords)).sorted() + keywords
  }

  static func serviceDate(for date: Date) -> String {
    date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
  }
}

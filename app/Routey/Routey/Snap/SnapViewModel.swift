import Foundation
import Observation
import RouteyDomain
import RouteyModel
import RouteyOCR
import SQLiteData

@MainActor
@Observable
final class SnapViewModel {
  struct AddedSummary: Equatable {
    var title: String
    var message: String?
    var signatureCount: Int
  }

  enum Phase: Equatable {
    case capturing
    case reading
    case result(SnapMatchResult)
    case added(AddedSummary)
    case failed(String)
  }

  private(set) var phase: Phase = .capturing
  let route: Route?

  private let database: any DatabaseWriter
  private var lastAddedParcelID: UUID?

  init(route: Route?, database: any DatabaseWriter) {
    self.route = route
    self.database = database
  }

  func handleCapturedImage(_ data: Data) async {
    phase = .reading
    do {
      let contexts: [RouteAddressContext]
      if let route {
        contexts = try await database.read { db in
          try RouteAddressLookup.contexts(routeID: route.id, in: db)
        }
      } else {
        contexts = []
      }
      let candidates = contexts.map(Self.candidate(from:))
      let words = Self.customWords(from: contexts.map(\.address))
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
      // Service date is intentionally stamped at accept time, not capture time:
      // a parcel belongs to the run it's confirmed into. (Domain decision, 2026-06-29.)
      let serviceDate = ServiceDate.local(for: .now)
      guard let addressID else {
        let temporaryResult = try TemporaryRouteBuilder.addParcelToTemporaryRouteWithResult(
          TemporaryParcelInput(
            serviceDate: serviceDate,
            labelSnapshot: input.labelSnapshot,
            civicNumber: result.components.civicNumber,
            street: temporaryStreet(from: result.components),
            postalCode: result.components.postalCode,
            trackingCode: input.trackingCode,
            trackingSymbology: input.trackingSymbology,
            requiresSignature: input.requiresSignature,
            isCustoms: input.isCustoms,
            toDoor: input.toDoor
          ),
          into: database
        )
        lastAddedParcelID = temporaryResult.parcelID
        let count = try RunOperations.signatureCount(runID: temporaryResult.runID, in: database)
        phase = .added(
          AddedSummary(
            title: "Added to Parcel Pile",
            message: "You can sort this run before leaving.",
            signatureCount: count
          )
        )
        return
      }

      guard let route else {
        phase = .failed("Import a route to add matched parcels.")
        return
      }

      let runID = try RunGeneration.generate(
        routeID: route.id, serviceDate: serviceDate, now: .now, into: database
      )
      let parcelID = try RunOperations.addParcel(
        runID: runID,
        addressID: addressID,
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
      let candidate = result.ranked.first { $0.id == addressID }?.candidate
      phase = .added(
        AddedSummary(
          title: "Parcel added",
          message: candidate.flatMap(Self.confirmationMessage(for:)),
          signatureCount: count
        )
      )
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

  func failCapture(_ message: String) {
    phase = .failed(message)
  }

  func reset() {
    phase = .capturing
  }

  static func customWords(from addresses: [Address]) -> [String] {
    let streetWords = addresses.flatMap { $0.street.split(separator: " ").map(String.init) }
    let keywords = ["RR", "CONC", "HWY", "LOT", "SS", "PO", "BOX"]
    return Array(Set(streetWords)).sorted() + keywords
  }

  static func candidate(from context: RouteAddressContext) -> AddressCandidate {
    AddressCandidate(
      id: context.address.id,
      civicNumber: context.address.civicNumber,
      civicRangeFrom: context.address.civicRangeFrom,
      civicRangeTo: context.address.civicRangeTo,
      suite: context.address.suite,
      street: context.address.street,
      occupantName: context.address.occupantName,
      postalCode: context.address.postalCode,
      locator: context.locator.isEmpty ? nil : context.locator,
      tagNames: context.tagNames,
      warningTagNames: context.warningTagNames
    )
  }

  static func confirmationMessage(for candidate: AddressCandidate) -> String? {
    let preferenceTags = candidate.tagNames.filter { !candidate.warningTagNames.contains($0) }
    let lines = [
      candidate.locator,
      candidate.warningTagNames.isEmpty
        ? nil
        : "Warning: \(candidate.warningTagNames.joined(separator: " · "))",
      preferenceTags.isEmpty
        ? nil
        : "Preference: \(preferenceTags.joined(separator: " · "))",
    ]
    .compactMap(\.self)

    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }

  private func temporaryStreet(from components: AddressComponents) -> String {
    components.streetTokens
      .map { $0.capitalized }
      .joined(separator: " ")
  }
}

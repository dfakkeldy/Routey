import Foundation
import Testing
@testable import RouteyOCR

@Suite struct SnapPipelineTests {
  @Test func assemblesReadoutMatchingAndFlags() async throws {
    let matchedID = UUID()
    let pipeline = SnapPipeline(
      reader: StubLabelReader(
        readout: LabelReadout(
          lines: [
            "SIGNATURE REQUIRED",
            "Alex Reed",
            "31 Elm St",
          ],
          barcodes: ["ZX-001"]
        )
      ),
      candidateProvider: { _ in
        [
          AddressCandidate(id: matchedID, civicNumber: 31, street: "Elm Street", occupantName: "Alex Reed")
        ]
      }
    )

    let result = try await pipeline.process()

    #expect(result.band == .autoAccept(matchedID))
    #expect(result.flags.contains(.signature))
    #expect(result.readout.barcodes == ["ZX-001"])
    #expect(result.components.occupant == "alex reed")
  }

  @Test func keywordLineAfterAddressDoesNotPolluteStreetTokens() async throws {
    let matchedID = UUID()
    let pipeline = SnapPipeline(
      reader: StubLabelReader(
        readout: LabelReadout(
          lines: [
            "31 Elm St",
            "SIGNATURE REQUIRED",
            "Alex Reed",
          ]
        )
      ),
      candidateProvider: { _ in
        [
          AddressCandidate(id: matchedID, civicNumber: 31, street: "Elm Street", occupantName: "Alex Reed")
        ]
      }
    )

    let result = try await pipeline.process()

    #expect(result.components.streetTokens == ["elm", "street"])
    #expect(result.band == .autoAccept(matchedID))
    #expect(result.flags.contains(.signature))
  }

  @Test func postalOnlyReadoutDoesNotAutoAcceptNoCivicCandidate() async throws {
    let candidateID = UUID()
    let pipeline = SnapPipeline(
      reader: StubLabelReader(
        readout: LabelReadout(lines: ["A1A 1X0"])
      ),
      candidateProvider: { _ in
        [
          AddressCandidate(id: candidateID, street: "", postalCode: "A1A 1X0")
        ]
      }
    )

    let result = try await pipeline.process()

    #expect(result.components.postalCode == "a1a1x0")
    #expect(result.components.streetTokens.isEmpty)
    #expect(result.band == .noMatch)
  }
}

private struct StubLabelReader: LabelReading {
  let readout: LabelReadout

  func read() async throws -> LabelReadout {
    readout
  }
}

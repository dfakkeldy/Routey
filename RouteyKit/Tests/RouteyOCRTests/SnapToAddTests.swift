import Foundation
import Testing
@testable import RouteyOCR

@Suite struct SnapToAddTests {
  @Test func mapsFlagsAndReadoutToParcelInput() {
    let addressID = UUID()
    let result = SnapMatchResult(
      band: .autoAccept(addressID),
      ranked: [],
      flags: [.signature, .customs],
      readout: LabelReadout(lines: ["31 Elm St", "Alex Reed"], barcodes: ["ZX-001"]),
      components: AddressComponents()
    )

    let input = SnapToAdd.parcelInputs(from: result, addressID: addressID)

    #expect(input.addressID == addressID)
    #expect(input.source == "ocr")
    #expect(input.requiresSignature)
    #expect(input.isCustoms)
    #expect(input.toDoor == false)
    #expect(input.labelSnapshot == "31 Elm St\nAlex Reed")
    #expect(input.trackingCode == "ZX-001")
    #expect(input.trackingSymbology == "")
  }

  @Test func noBarcodeOrFlagsYieldsEmptyDefaults() {
    let result = SnapMatchResult(
      band: .noMatch, ranked: [], flags: [],
      readout: LabelReadout(lines: ["12 Maple Rd"]),
      components: AddressComponents()
    )

    let input = SnapToAdd.parcelInputs(from: result, addressID: nil)

    #expect(input.addressID == nil)
    #expect(input.requiresSignature == false)
    #expect(input.isCustoms == false)
    #expect(input.trackingCode == "")
    #expect(input.labelSnapshot == "12 Maple Rd")
  }
}

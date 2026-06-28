import Testing
@testable import RouteyOCR

@Suite struct LabelKeywordDetectorTests {
  @Test func detectsSignatureRequiredInEnglishAndFrench() {
    #expect(LabelKeywordDetector.detect(in: "SIGNATURE REQUIRED").contains(.signature))
    #expect(LabelKeywordDetector.detect(in: "signature requise").contains(.signature))
  }

  @Test func detectsCustomsStyleLabels() {
    #expect(LabelKeywordDetector.detect(in: "CUSTOMS DUTY 4.50").contains(.customs))
    #expect(LabelKeywordDetector.detect(in: "declaration de douane").contains(.customs))
  }

  @Test func detectsRegisteredStyleHandling() {
    #expect(LabelKeywordDetector.detect(in: "REGISTERED HANDLING").contains(.registered))
    #expect(LabelKeywordDetector.detect(in: "envoi recommande").contains(.registered))
  }

  @Test func plainLabelHasNoFlags() {
    #expect(LabelKeywordDetector.detect(in: "Rowan Vale\n41 Maple Rd").isEmpty)
  }
}

#if os(iOS) || os(macOS)
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
@testable import RouteyOCR

@Suite struct VisionLabelReaderTests {
  @Test func recognizesRenderedLabelText() async throws {
    let data = try Self.renderLabelPNG(lines: ["31 ELM ST", "ALEX REED", "SIGNATURE REQUIRED"])
    let reader = VisionLabelReader(imageData: data, customWords: ["ELM"])

    let readout = try await reader.read()

    #expect(!readout.lines.isEmpty)
    #expect(readout.lines.contains { $0.localizedCaseInsensitiveContains("elm") })
  }

  @Test func throwsOnUndecodableImage() async {
    let reader = VisionLabelReader(imageData: Data([0x00, 0x01, 0x02]))
    await #expect(throws: LabelReaderError.undecodableImage) {
      _ = try await reader.read()
    }
  }

  // Renders high-contrast black-on-white text to PNG Data using Core Text + ImageIO.
  // Cross-platform (no UIKit/AppKit); gives Vision an easy, deterministic OCR target.
  static func renderLabelPNG(lines: [String], width: Int = 700, height: Int = 400) throws -> Data {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw RenderError.context }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))

    let font = CTFontCreateWithName("Helvetica" as CFString, 44, nil)
    var y = height - 80
    for line in lines {
      let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font
      ]
      let attributed = NSAttributedString(string: line, attributes: attributes)
      let ctLine = CTLineCreateWithAttributedString(attributed)
      context.textPosition = CGPoint(x: 40, y: CGFloat(y))
      CTLineDraw(ctLine, context)
      y -= 80
    }

    guard let image = context.makeImage() else { throw RenderError.image }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else {
      throw RenderError.destination
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw RenderError.finalize }
    return out as Data
  }

  enum RenderError: Error { case context, image, destination, finalize }
}
#endif

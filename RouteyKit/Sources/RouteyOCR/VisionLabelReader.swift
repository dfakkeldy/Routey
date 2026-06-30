#if os(iOS) || os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Vision

public enum LabelReaderError: Error, Equatable {
  case undecodableImage
}

public struct VisionLabelReader: LabelReading {
  public var imageData: Data
  public var customWords: [String]
  public var recognitionLanguages: [String]

  public init(
    imageData: Data,
    customWords: [String] = [],
    recognitionLanguages: [String] = ["en-CA", "fr-CA"]
  ) {
    self.imageData = imageData
    self.customWords = customWords
    self.recognitionLanguages = recognitionLanguages
  }

  public func read() async throws -> LabelReadout {
    let data = imageData
    let words = customWords
    let languages = recognitionLanguages

    // Run Vision off the calling actor/thread (perform is blocking).
    return try await Task.detached(priority: .userInitiated) {
      guard
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else {
        throw LabelReaderError.undecodableImage
      }

      let textRequest = VNRecognizeTextRequest()
      textRequest.recognitionLevel = .accurate
      textRequest.usesLanguageCorrection = false
      textRequest.recognitionLanguages = languages
      textRequest.customWords = words

      let barcodeRequest = VNDetectBarcodesRequest()

      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      try handler.perform([textRequest, barcodeRequest])

      let lines = (textRequest.results ?? [])
        .compactMap { $0.topCandidates(1).first?.string }
      let barcodes = (barcodeRequest.results ?? [])
        .compactMap { $0.payloadStringValue }

      return LabelReadout(lines: lines, barcodes: barcodes)
    }.value
  }
}
#endif

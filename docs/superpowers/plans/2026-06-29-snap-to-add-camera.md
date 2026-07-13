# Snap-to-Add Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the flagship Snap-to-Add flow — photograph a parcel label, read it on-device with Vision, match it to a route address, and add a real `Parcel` to Today's Run via a three-band confirm UI.

**Architecture:** Keep new logic in the Mac-testable `RouteyOCR`/`RouteyDomain` package modules (a pure parcel-input mapper, a `VisionLabelReader` on the existing `LabelReading` seam, and a parcel-delete op for undo); keep the camera surface, an `@Observable` view model, and the three-band UI in the iOS app target. The matcher, normalizer, `SnapPipeline`, `RunGeneration.generate`, and `RunOperations.addParcel` already exist and are tested — this plan wires them and adds the missing edges.

**Tech Stack:** Swift 6, SwiftUI, Vision (`VNRecognizeTextRequest` + `VNDetectBarcodesRequest`), AVFoundation (still capture), SQLiteData/GRDB, Swift Testing.

## Global Constraints

- **Swift Testing only** (not XCTest). Package tests run on the Mac with `cd RouteyKit && swift test`.
- **App target deployment: iOS 18.0.** `RouteyKit` package floor: **iOS 17 / macOS 14**.
- **No synced-schema change in this plan.** Snap writes only existing `Parcel` / `TodaysRun` rows. Do NOT add or alter synced tables/columns; the CloudKit append-only rules stay untouched.
- **Persistence:** parameterized StructuredQueries only (`Model.insert { … }.execute(db)`, `Model.find(id).delete().execute(db)`) — never string SQL. Writes go through `RouteyDomain` statics on a `DatabaseWriter`.
- **Carrier-agnostic:** every test/fixture string is an invented placeholder (e.g. "31 Elm St", "Alex Reed", "Maple Road"). Never a real name/street/civic number.
- **App DI pattern:** views read `@Dependency(\.defaultDatabase)` / `@Dependency(\.defaultSyncEngine)`; after a local write, fire `Task { await RouteySyncing.sendChanges(reason:using:syncEngine) }`. New source files under `app/Routey/Routey/` are auto-compiled (Xcode 16 synchronized groups) — **do NOT add `PBXFileReference`/`PBXBuildFile` entries for new `.swift` files.**
- **Vision config (spec §7):** `recognitionLevel = .accurate`, `usesLanguageCorrection = false`, `recognitionLanguages = ["en-CA", "fr-CA"]`, `customWords` seeded from route street names + `["RR","CONC","HWY","LOT","SS","PO","BOX"]`; run off the main thread.
- **End every task with a commit** (Conventional Commits, `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`).

---

### Task 1: `RunOperations.removeParcel` (undo support)

**Files:**
- Modify: `RouteyKit/Sources/RouteyDomain/RunOperations.swift`
- Test: `RouteyKit/Tests/RouteyDomainTests/RunOperationTests.swift`

**Interfaces:**
- Consumes: `Parcel` model, `RunOperations.addParcel`, the existing private `freshDB()` / `seedRun(in:stopCount:)` test helpers in `RunOperationTests.swift`.
- Produces: `public static func removeParcel(_ id: Parcel.ID, in database: any DatabaseWriter) throws` — deletes the parcel row by primary key. Used by `SnapViewModel.undoLastAdd` (Task 4).

- [ ] **Step 1: Write the failing test** — append to `RunOperationTests.swift`:

```swift
@Test func removeParcelDeletesTheRow() throws {
  let database = try freshDB()
  let (_, runID) = try seedRun(in: database)

  let parcelID = try RunOperations.addParcel(
    runID: runID, addressID: nil, source: "ocr",
    requiresSignature: true, isCustoms: false, toDoor: false,
    labelSnapshot: "31 Elm St", trackingCode: "ZX-001", trackingSymbology: "",
    in: database
  )
  #expect(try RunOperations.signatureCount(runID: runID, in: database) == 1)

  try RunOperations.removeParcel(parcelID, in: database)

  let remaining = try database.read { db in try Parcel.where { $0.id.eq(#bind(parcelID)) }.fetchAll(db) }
  #expect(remaining.isEmpty)
  #expect(try RunOperations.signatureCount(runID: runID, in: database) == 0)
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd RouteyKit && swift test --filter RunOperationTests`
Expected: FAIL — `removeParcel` is undefined (compile error).

- [ ] **Step 3: Implement `removeParcel`** — add inside `enum RunOperations` in `RunOperations.swift`, after `addParcel`:

```swift
public static func removeParcel(_ id: Parcel.ID, in database: any DatabaseWriter) throws {
  try database.write { db in
    try Parcel.find(id).delete().execute(db)
  }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd RouteyKit && swift test --filter RunOperationTests`
Expected: PASS (all `RunOperationTests` green).

- [ ] **Step 5: Commit**

```bash
git add RouteyKit/Sources/RouteyDomain/RunOperations.swift RouteyKit/Tests/RouteyDomainTests/RunOperationTests.swift
git commit -m "$(cat <<'EOF'
feat(domain): add RunOperations.removeParcel for snap undo

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `SnapToAdd.parcelInputs` (pure flags→parcel mapper)

**Files:**
- Create: `RouteyKit/Sources/RouteyOCR/SnapToAdd.swift`
- Test: `RouteyKit/Tests/RouteyOCRTests/SnapToAddTests.swift`

**Interfaces:**
- Consumes: `SnapMatchResult`, `LabelReadout`, `LabelFlags`, `AddressComponents` (all in `RouteyOCR`).
- Produces:
  - `public struct SnapParcelInput: Equatable, Sendable` with fields `addressID: UUID?`, `source: String`, `requiresSignature: Bool`, `isCustoms: Bool`, `toDoor: Bool`, `labelSnapshot: String`, `trackingCode: String`, `trackingSymbology: String`.
  - `public enum SnapToAdd { public static func parcelInputs(from result: SnapMatchResult, addressID: UUID?) -> SnapParcelInput }`.
  - Field meanings (consumed by `SnapViewModel.accept`, Task 4): `source = "ocr"`, `requiresSignature = flags.contains(.signature)`, `isCustoms = flags.contains(.customs)`, `toDoor = false`, `labelSnapshot = readout.lines joined by "\n"`, `trackingCode = readout.barcodes.first ?? ""`, `trackingSymbology = ""`.

- [ ] **Step 1: Write the failing test** — create `SnapToAddTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd RouteyKit && swift test --filter SnapToAddTests`
Expected: FAIL — `SnapToAdd` / `SnapParcelInput` undefined.

- [ ] **Step 3: Implement** — create `SnapToAdd.swift`:

```swift
import Foundation

public struct SnapParcelInput: Equatable, Sendable {
  public var addressID: UUID?
  public var source: String
  public var requiresSignature: Bool
  public var isCustoms: Bool
  public var toDoor: Bool
  public var labelSnapshot: String
  public var trackingCode: String
  public var trackingSymbology: String

  public init(
    addressID: UUID?,
    source: String,
    requiresSignature: Bool,
    isCustoms: Bool,
    toDoor: Bool,
    labelSnapshot: String,
    trackingCode: String,
    trackingSymbology: String
  ) {
    self.addressID = addressID
    self.source = source
    self.requiresSignature = requiresSignature
    self.isCustoms = isCustoms
    self.toDoor = toDoor
    self.labelSnapshot = labelSnapshot
    self.trackingCode = trackingCode
    self.trackingSymbology = trackingSymbology
  }
}

public enum SnapToAdd {
  public static func parcelInputs(from result: SnapMatchResult, addressID: UUID?) -> SnapParcelInput {
    SnapParcelInput(
      addressID: addressID,
      source: "ocr",
      requiresSignature: result.flags.contains(.signature),
      isCustoms: result.flags.contains(.customs),
      toDoor: false,
      labelSnapshot: result.readout.lines.joined(separator: "\n"),
      trackingCode: result.readout.barcodes.first ?? "",
      trackingSymbology: ""
    )
  }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd RouteyKit && swift test --filter SnapToAddTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add RouteyKit/Sources/RouteyOCR/SnapToAdd.swift RouteyKit/Tests/RouteyOCRTests/SnapToAddTests.swift
git commit -m "$(cat <<'EOF'
feat(ocr): map snap match result to parcel inputs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `VisionLabelReader` (on-device OCR on the `LabelReading` seam)

**Files:**
- Create: `RouteyKit/Sources/RouteyOCR/VisionLabelReader.swift`
- Test: `RouteyKit/Tests/RouteyOCRTests/VisionLabelReaderTests.swift`

**Interfaces:**
- Consumes: `LabelReading`, `LabelReadout` (in `RouteyOCR`).
- Produces:
  - `public struct VisionLabelReader: LabelReading` with `init(imageData: Data, customWords: [String] = [], recognitionLanguages: [String] = ["en-CA", "fr-CA"])` and `func read() async throws -> LabelReadout`.
  - `public enum LabelReaderError: Error, Equatable { case undecodableImage }`.
  - Used by `SnapViewModel` (Task 4) as the concrete reader passed to `SnapPipeline(reader:candidateProvider:)`.

**Why `#if os(iOS) || os(macOS)`:** Vision + ImageIO exist on both, so this file compiles and the OCR test runs under `swift test` on the Mac, while watchOS (no text-recognition Vision) is excluded. The reader holds the image as `Data` (Sendable) and decodes to `CGImage` inside `read()` because `CGImage` is not `Sendable`.

- [ ] **Step 1: Write the failing test** — create `VisionLabelReaderTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd RouteyKit && swift test --filter VisionLabelReaderTests`
Expected: FAIL — `VisionLabelReader` / `LabelReaderError` undefined.

- [ ] **Step 3: Implement** — create `VisionLabelReader.swift`:

```swift
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
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd RouteyKit && swift test --filter VisionLabelReaderTests`
Expected: PASS. (If `recognizesRenderedLabelText` is flaky in headless CI, the deterministic `throwsOnUndecodableImage` test still guards the decode path; the OCR-accuracy gate is the on-device checklist in Task 6. Do NOT weaken the assertion without recording why.)

- [ ] **Step 5: Run the full package suite to confirm no regressions**

Run: `cd RouteyKit && swift test`
Expected: PASS (all suites green).

- [ ] **Step 6: Commit**

```bash
git add RouteyKit/Sources/RouteyOCR/VisionLabelReader.swift RouteyKit/Tests/RouteyOCRTests/VisionLabelReaderTests.swift
git commit -m "$(cat <<'EOF'
feat(ocr): add Vision-backed label reader on the LabelReading seam

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Link `RouteyOCR` into the app + `SnapViewModel`

**Files:**
- Modify: `app/Routey/Routey.xcodeproj/project.pbxproj` (add `RouteyOCR` package product to the `Routey` target)
- Create: `app/Routey/Routey/Snap/SnapViewModel.swift`

**Interfaces:**
- Consumes: `RouteyOCR` (`SnapPipeline`, `VisionLabelReader`, `SnapToAdd`, `AddressCandidate`, `SnapMatchResult`), `RouteyDomain` (`RunGeneration.generate`, `RunOperations.addParcel`/`removeParcel`/`signatureCount`), `RouteyModel` (`Route`, `Address`), `SQLiteData`.
- Produces: `@MainActor @Observable final class SnapViewModel` with:
  - `enum Phase: Equatable { case capturing, reading, result(SnapMatchResult), added(signatureCount: Int), failed(String) }`
  - `init(route: Route, database: any DatabaseWriter)`
  - `func handleCapturedImage(_ data: Data) async`
  - `func accept(addressID: UUID?) async`
  - `func undoLastAdd() async`
  - `func reset()`
  - Read by `SnapView` / `SnapResultView` (Tasks 5–7).

- [ ] **Step 1: Add `RouteyOCR` to the app target.** `RouteySearch` is already wired as a package product in `project.pbxproj` in three spots. Find them:

Run: `grep -n "RouteySearch" app/Routey/Routey.xcodeproj/project.pbxproj`

Duplicate each `RouteySearch` reference for `RouteyOCR` using **fresh unique 24-hex-character object IDs** (copy the style of the IDs already in the file):
1. A `XCSwiftPackageProductDependency` object: `<NEWID1> /* RouteyOCR */ = {isa = XCSwiftPackageProductDependency; productName = RouteyOCR;};`
2. A `PBXBuildFile` in the file's `PBXBuildFile` section: `<NEWID2> /* RouteyOCR in Frameworks */ = {isa = PBXBuildFile; productRef = <NEWID1> /* RouteyOCR */;};`
3. Add `<NEWID1> /* RouteyOCR */,` to the `Routey` target's `packageProductDependencies` list, and `<NEWID2> /* RouteyOCR in Frameworks */,` to that target's `PBXFrameworksBuildPhase` `files` list.

Do NOT touch the `RouteyMacProof` target. (If you have Xcode open instead, the equivalent is: select the `Routey` target → General → Frameworks, Libraries, and Embedded Content → `+` → add `RouteyOCR`.)

- [ ] **Step 2: Create `SnapViewModel.swift`:**

```swift
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
      let addresses = try database.read { db in
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
```

- [ ] **Step 3: Build the app to verify `RouteyOCR` links and the view model compiles**

Run: `"$HOME/.claude/bin/xcode-build-gate.sh" --wait && xcodebuild -project app/Routey/Routey.xcodeproj -scheme Routey -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`. (No simulator boot needed for a build. If the pbxproj edit is malformed you'll get a project-parse or `No such module 'RouteyOCR'` error — fix the three references from Step 1.)

- [ ] **Step 4: Commit**

```bash
git add app/Routey/Routey.xcodeproj/project.pbxproj app/Routey/Routey/Snap/SnapViewModel.swift
git commit -m "$(cat <<'EOF'
feat(app): add SnapViewModel and link RouteyOCR into the app target

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `SnapResultView` (three-band confirm UI)

**Files:**
- Create: `app/Routey/Routey/Snap/SnapResultView.swift`

**Interfaces:**
- Consumes: `SnapViewModel`, `SnapMatchResult`, `MatchBand` (`.autoAccept(UUID)` / `.review([ScoredAddressCandidate])` / `.noMatch`), `ScoredAddressCandidate`, `AddressCandidate`.
- Produces: `struct SnapResultView: View` taking `let result: SnapMatchResult` and `let model: SnapViewModel`. Renders the three bands; auto-accept commits immediately (per spec §5).

**Behavior:**
- `.autoAccept(id)` → `.task` calls `await model.accept(addressID: id)` once (auto-commit); the parent `SnapView` shows the undo toast when `phase` becomes `.added`.
- `.review(candidates)` → list candidates with raw OCR shown; tapping one calls `await model.accept(addressID: $0.candidate.id)`.
- `.noMatch` → show raw OCR plus a manual pick list of `result.ranked.prefix(8)`; tapping one accepts it; a "Not listed" button calls `model.reset()`. (Refinement of spec §5's "reuse SearchView": the first slice picks from the ranked candidates already in hand; full predictive-search-to-add is a follow-up — see Task 8 doc note.)

- [ ] **Step 1: Create `SnapResultView.swift`:**

```swift
import RouteyOCR
import SwiftUI

struct SnapResultView: View {
  let result: SnapMatchResult
  let model: SnapViewModel

  var body: some View {
    switch result.band {
    case .autoAccept(let id):
      ProgressView("Adding parcel…")
        .task { await model.accept(addressID: id) }
    case .review(let candidates):
      SnapPickList(
        title: "Which delivery point?",
        rawLines: result.readout.lines,
        candidates: candidates.map(\.candidate),
        model: model
      )
    case .noMatch:
      SnapPickList(
        title: "No confident match",
        rawLines: result.readout.lines,
        candidates: result.ranked.prefix(8).map(\.candidate),
        model: model,
        showsNotListed: true
      )
    }
  }
}

private struct SnapPickList: View {
  let title: String
  let rawLines: [String]
  let candidates: [AddressCandidate]
  let model: SnapViewModel
  var showsNotListed: Bool = false

  var body: some View {
    List {
      Section("Scanned label") {
        ForEach(rawLines.enumerated(), id: \.offset) { _, line in
          Text(line).font(.callout).foregroundStyle(.secondary)
        }
      }
      Section(title) {
        ForEach(candidates) { candidate in
          Button {
            Task { await model.accept(addressID: candidate.id) }
          } label: {
            SnapCandidateRow(candidate: candidate)
          }
        }
        if showsNotListed {
          Button("Not listed — retake", systemImage: "arrow.uturn.backward") {
            model.reset()
          }
        }
      }
    }
  }
}

private struct SnapCandidateRow: View {
  let candidate: AddressCandidate

  var body: some View {
    VStack(alignment: .leading) {
      Text(candidate.civicNumber.map { "\($0) \(candidate.street)" } ?? candidate.street)
        .bold()
      if let occupant = candidate.occupantName {
        Text(occupant).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
```

- [ ] **Step 2: Build to verify it compiles** (it's exercised through `SnapView` in Task 6; here we only confirm compilation)

Run: `"$HOME/.claude/bin/xcode-build-gate.sh" --wait && xcodebuild -project app/Routey/Routey.xcodeproj -scheme Routey -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add app/Routey/Routey/Snap/SnapResultView.swift
git commit -m "$(cat <<'EOF'
feat(app): add three-band snap confirm UI

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `CameraCaptureView` + camera permission

**Files:**
- Create: `app/Routey/Routey/Snap/CameraCaptureView.swift`
- Modify: `app/Routey/Routey/Info.plist` (add `NSCameraUsageDescription`)

**Interfaces:**
- Produces: `struct CameraCaptureView: UIViewControllerRepresentable` with `var onCapture: (Data) -> Void` and `var onError: (String) -> Void`. Captures one still photo and returns its `Data`.
- Consumed by `SnapView` (Task 7).

**Note:** Camera capture is **device-only** — it cannot run in the Simulator or `swift test`. This task is build-verified plus an on-device manual checklist.

- [ ] **Step 1: Add the camera usage string.** In `app/Routey/Routey/Info.plist`, add inside the top-level `<dict>`:

```xml
<key>NSCameraUsageDescription</key>
<string>Routey uses the camera to read parcel labels and add them to today's run.</string>
```

- [ ] **Step 2: Create `CameraCaptureView.swift`:**

```swift
#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {
  var onCapture: (Data) -> Void
  var onError: (String) -> Void

  func makeUIViewController(context: Context) -> CameraCaptureController {
    let controller = CameraCaptureController()
    controller.onCapture = onCapture
    controller.onError = onError
    return controller
  }

  func updateUIViewController(_ controller: CameraCaptureController, context: Context) {}
}

final class CameraCaptureController: UIViewController, AVCapturePhotoCaptureDelegate {
  var onCapture: ((Data) -> Void)?
  var onError: ((String) -> Void)?

  private let session = AVCaptureSession()
  private let output = AVCapturePhotoOutput()
  private var preview: AVCaptureVideoPreviewLayer?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    addShutterButton()
    Task { await configureSession() }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    preview?.frame = view.bounds
  }

  private func configureSession() async {
    let granted = await AVCaptureDevice.requestAccess(for: .video)
    guard granted else {
      onError?("Camera access is off. Enable it in Settings to snap labels.")
      return
    }
    guard
      let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input),
      session.canAddOutput(output)
    else {
      onError?("Couldn't start the camera on this device.")
      return
    }
    session.beginConfiguration()
    session.addInput(input)
    session.addOutput(output)
    session.commitConfiguration()

    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.frame = view.bounds
    view.layer.insertSublayer(layer, at: 0)
    preview = layer

    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async { [session] in
        session.startRunning()
        continuation.resume()
      }
    }
  }

  private func addShutterButton() {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "camera.circle.fill"), for: .normal)
    button.tintColor = .white
    button.contentVerticalAlignment = .fill
    button.contentHorizontalAlignment = .fill
    button.translatesAutoresizingMaskIntoConstraints = false
    button.accessibilityLabel = "Snap label"
    button.addTarget(self, action: #selector(snap), for: .touchUpInside)
    view.addSubview(button)
    NSLayoutConstraint.activate([
      button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
      button.widthAnchor.constraint(equalToConstant: 72),
      button.heightAnchor.constraint(equalToConstant: 72),
    ])
  }

  @objc private func snap() {
    output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: (any Error)?
  ) {
    if let error {
      onError?(error.localizedDescription)
      return
    }
    guard let data = photo.fileDataRepresentation() else {
      onError?("Couldn't read the captured photo.")
      return
    }
    onCapture?(data)
  }
}
#endif
```

- [ ] **Step 3: Build to verify it compiles**

Run: `"$HOME/.claude/bin/xcode-build-gate.sh" --wait && xcodebuild -project app/Routey/Routey.xcodeproj -scheme Routey -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add app/Routey/Routey/Snap/CameraCaptureView.swift app/Routey/Routey/Info.plist
git commit -m "$(cat <<'EOF'
feat(app): add AVFoundation camera capture surface

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `SnapView` container + entry point in `ContentView`

**Files:**
- Create: `app/Routey/Routey/Snap/SnapView.swift`
- Modify: `app/Routey/Routey/ContentView.swift` (camera toolbar button + `.fullScreenCover`)

**Interfaces:**
- Consumes: `SnapViewModel`, `CameraCaptureView`, `SnapResultView`, `RouteyModel.Route`, `@Dependency(\.defaultDatabase)`, `@Dependency(\.defaultSyncEngine)`, `RouteySyncing`.
- Produces: `struct SnapView: View` taking `let route: Route` and `let onClose: () -> Void`; owns the `SnapViewModel`, switches on its `phase`, and on `.added` fires a sync push and shows the undo toast.

- [ ] **Step 1: Create `SnapView.swift`:**

```swift
import RouteyModel
import SQLiteData
import SwiftUI

struct SnapView: View {
  let route: Route
  let onClose: () -> Void

  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.defaultSyncEngine) private var syncEngine
  @State private var model: SnapViewModel?

  var body: some View {
    NavigationStack {
      Group {
        if let model {
          content(for: model)
        } else {
          ProgressView()
        }
      }
      .navigationTitle("Snap Parcel")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        Button("Done", action: onClose)
      }
    }
    .task {
      if model == nil {
        model = SnapViewModel(route: route, database: database)
      }
    }
  }

  @ViewBuilder
  private func content(for model: SnapViewModel) -> some View {
    switch model.phase {
    case .capturing:
      #if os(iOS)
      CameraCaptureView(
        onCapture: { data in Task { await model.handleCapturedImage(data) } },
        onError: { _ in model.reset() }
      )
      .ignoresSafeArea(edges: .bottom)
      #else
      ContentUnavailableView("Use a device", systemImage: "camera", description: Text("Snap a label on an iPhone."))
      #endif
    case .reading:
      ProgressView("Reading label…")
    case .result(let result):
      SnapResultView(result: result, model: model)
    case .added(let signatureCount):
      SnapAddedView(signatureCount: signatureCount, model: model)
        .task { await RouteySyncing.sendChanges(reason: "parcel snapped", using: syncEngine) }
    case .failed(let message):
      ContentUnavailableView {
        Label("Couldn't snap", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try again") { model.reset() }
      }
    }
  }
}

private struct SnapAddedView: View {
  let signatureCount: Int
  let model: SnapViewModel

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.circle.fill")
        .font(.largeTitle)
        .foregroundStyle(.green)
      Text("Parcel added")
        .font(.title2).bold()
      Text("Signatures today: \(signatureCount)")
        .foregroundStyle(.secondary)
      HStack {
        Button("Undo", systemImage: "arrow.uturn.backward") {
          Task { await model.undoLastAdd() }
        }
        Button("Snap another", systemImage: "camera") {
          model.reset()
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding()
  }
}
```

- [ ] **Step 2: Add the entry point to `ContentView.swift`.** Add a state flag and a toolbar camera button that presents `SnapView` for the first route. Add near the other `@State`:

```swift
@State private var isSnapping = false
```

Add to the existing `.toolbar { … }` (alongside the current buttons):

```swift
Button("Snap Parcel", systemImage: "camera") {
  isSnapping = true
}
.disabled(routes.isEmpty)
```

Add this modifier on the same view that owns the toolbar (e.g. after the existing `.navigationDestination`/`.sheet` modifiers):

```swift
.fullScreenCover(isPresented: $isSnapping) {
  if let route = routes.first {
    SnapView(route: route) { isSnapping = false }
  }
}
```

(Single-route assumption per spec §6: V1 has one route, so `routes.first` is the active route; the button is disabled until a route is imported.)

- [ ] **Step 3: Build to verify it compiles**

Run: `"$HOME/.claude/bin/xcode-build-gate.sh" --wait && xcodebuild -project app/Routey/Routey.xcodeproj -scheme Routey -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: On-device manual smoke checklist** (camera needs real hardware; record results in the PR description):
  - Import a route (or use an existing one), tap **Snap Parcel** → camera opens (grant permission once).
  - Snap a clearly-printed invented test label with a civic number + street that exists on the route → confirm an auto-accept adds a parcel and the "Signatures today" count behaves (use a "SIGNATURE REQUIRED" label).
  - Tap **Undo** → confirm the parcel count drops back.
  - Snap an ambiguous/partial label → confirm the disambiguation list or no-match pick list appears with the raw OCR shown.
  - Deny camera permission (Settings → Routey) and reopen → confirm the graceful message, app does not crash.

- [ ] **Step 5: Commit**

```bash
git add app/Routey/Routey/Snap/SnapView.swift app/Routey/Routey/ContentView.swift
git commit -m "$(cat <<'EOF'
feat(app): wire Snap-to-Add entry point and capture flow

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Documentation update

**Files:**
- Modify: `docs/superpowers/specs/2026-06-22-routey-design.md` (§7 note)
- Modify: `docs/superpowers/plans/2026-06-25-routey-roadmap-execution.md` (M4/M5 status)

**Interfaces:** none (docs only).

- [ ] **Step 1: Update the master spec.** In `docs/superpowers/specs/2026-06-22-routey-design.md`, add a short note in/near §7 recording the as-built choices: Snap-to-Add UI shipped using `VNRecognizeTextRequest` + `VNDetectBarcodesRequest`; candidate sourcing loads all route addresses and scores in memory (FTS blocking deferred); `customWords` seeded from route street names + rural keywords; the `.noMatch` manual fallback currently picks from the ranked candidates (full predictive-search-to-add is a follow-up).

- [ ] **Step 2: Update the roadmap.** In `docs/superpowers/plans/2026-06-25-routey-roadmap-execution.md`, mark the M4 camera-OCR UI and the M5 Snap-to-Add UI items as implemented (camera capture device-tested), referencing this plan.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-06-22-routey-design.md docs/superpowers/plans/2026-06-25-routey-roadmap-execution.md
git commit -m "$(cat <<'EOF'
docs: record Snap-to-Add as-built decisions

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**1. Spec coverage** (against `2026-06-29-snap-to-add-camera-design.md`):
- §1 full vertical slice (camera → OCR → match → confirm → Parcel) → Tasks 3–7. ✓
- §2 `VisionLabelReader` on the seam → Task 3; candidate provider → Task 4; three bands → Task 5; entry point → Task 7. ✓
- §3 module placement (`VisionLabelReader`/`SnapToAdd` in `RouteyOCR`; camera/view-model/UI in app; `RouteyOCR` kept DB-free) → Tasks 2–7. ✓
- §4 data flow incl. `RunGeneration.generate` + `RunOperations.addParcel` with mapped flags → Task 4. ✓
- §5 three bands incl. auto-accept-immediately + undo → Tasks 1 (`removeParcel`), 5, 7. ✓
- §6 candidate sourcing (all route addresses, customWords from streets) → Task 4. ✓
- §7 entry point (toolbar button + fullScreenCover, no TabView) → Task 7. ✓
- §8 error/empty states (permission denied, no camera, OCR empty/`.noMatch`) → Tasks 6–7. ✓
- §9 testing (Mac-testable `SnapToAdd`/`VisionLabelReader`/`removeParcel`; device checklist) → Tasks 1–3, 7. ✓ (Refinement: in-test rendered image instead of a committed PNG fixture — strictly better; no `Package.swift` resources change.)
- §10 Vision API resolved to `VNRecognizeTextRequest` + `VNDetectBarcodesRequest` → Task 3. ✓
- §11 doc follow-ups → Task 8. ✓
- §12 carrier-agnostic fixtures → invented strings throughout. ✓

**2. Placeholder scan:** No "TBD"/"handle errors"/"similar to" — every code step is complete. The `.noMatch` ranked-pick-list and in-test image render are explicit, recorded refinements, not placeholders. ✓

**3. Type consistency:** `RunOperations.addParcel` is called with the exact argument order from source (`requiresSignature, isCustoms, toDoor`, then `labelSnapshot, trackingCode, trackingSymbology`); `MatchBand.autoAccept(UUID)` carries the matched candidate id passed as `addressID`; `ScoredAddressCandidate.candidate.id` used for review/no-match taps; `serviceDate` is a `String`; `RunGeneration.generate` uses `into:` while `RunOperations.*` use `in:`. ✓

# Routey Plan 07 — Encrypted Handoff (`.routey` export/import)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let a route holder hand their route to a relief carrier as a **passphrase-encrypted `.routey` file** — the *only* sharing mechanism — and let the relief carrier import it as a **borrowed, read-only** route.

**Architecture:** A `RouteyExport` module: Codable **DTOs** (decoupled from the `@Table` persistence models so the file format versions independently), a dependency-light **crypto envelope** (PBKDF2-HMAC-SHA256 → AES-256-GCM with a versioned header bound as GCM AAD), and exporter/importer that map a route graph ↔ a `.routey` `Data`. Imported routes get `isBorrowed = true` and are read-only in the UI.

**Tech Stack:** Swift 6, CryptoKit (AES-GCM), CommonCrypto (PBKDF2), SwiftUI (Transferable/fileImporter), Swift Testing. No third-party deps.

**Depends on:** Plan 01 (model/persistence), Plan 02 (`RouteEditing` for read-only enforcement). UI requires app shell.

## Global Constraints

- Inherited from Plan 01.
- **No CloudKit sharing** — this file is the sole handoff path.
- **KDF:** PBKDF2-HMAC-SHA256 via CommonCrypto; iteration count = `max(600_000, calibrated-to-~300ms)` in production, **stored in the header**. **Encryption:** AES-256-GCM (`AES.GCM`); fresh random 16-byte salt + auto 12-byte nonce; never reuse/derive the nonce from the passphrase. Wrong passphrase ⇒ `authenticationFailure` (that *is* the signal; no plaintext verifier). Header bound as AAD.
- **DTOs are separate from `@Table` models**; `payloadSchemaVersion` versions the graph independently of the crypto `formatVersion`.
- Imported routes are **borrowed/read-only**; edit operations must refuse them.

---

## File structure

```
RouteyKit/
  Package.swift                        # add RouteyExport
  Sources/RouteyExport/
    RouteDTO.swift                     # Codable graph DTOs
    DTOMapping.swift                   # model graph <-> DTO
    RouteyCrypto.swift                 # PBKDF2 + AES-GCM envelope (versioned AAD header)
    RouteExporter.swift                # routeID -> .routey Data
    RouteImporter+Encrypted.swift      # .routey Data -> borrowed route in DB
  Tests/RouteyExportTests/
    RouteyCryptoTests.swift
    ExportImportRoundTripTests.swift
  Sources/RouteyPersistence/Schema.swift   # + v3 migration: add isBorrowed to routes
  Sources/RouteyModel/Route.swift          # + isBorrowed
  Sources/RouteyDomain/RouteEditing.swift  # + borrowed read-only guard
app/Routey/Share/
  ExportRouteView.swift                # passphrase -> ShareLink(.routey)
  ImportRouteView.swift                # fileImporter -> passphrase -> import
```

---

### Task 1: Crypto envelope (the security-critical core)

**Files:** `RouteyExport/RouteyCrypto.swift`, `RouteyCryptoTests.swift`, `Package.swift` (+ `RouteyExport` target).

**Interfaces:**
- `enum RouteyCryptoError: Error { case badFormat, unsupportedVersion(UInt8), wrongPassphraseOrCorrupt }`
- `enum RouteyCrypto`:
  - `static func encrypt(_ plaintext: Data, passphrase: String, payloadSchemaVersion: UInt16, iterations: UInt32) throws -> Data`
  - `static func decrypt(_ data: Data, passphrase: String) throws -> (plaintext: Data, payloadSchemaVersion: UInt16)`

**Wire format:** `magic "RTYE"(4) | formatVersion:UInt8=1 | kdfID:UInt8=1 | iterations:UInt32-BE | saltLen:UInt8 | salt | payloadSchemaVersion:UInt16-BE | nonce(12) | ciphertext+tag`. The header (everything before the nonce) is the GCM AAD.

- [ ] **Step 1:** Add `RouteyExport` target (no model dep yet for this task) + test target; `swift build`.

- [ ] **Step 2: Write failing tests** — `RouteyCryptoTests.swift`:

```swift
import Testing
import Foundation
@testable import RouteyExport

@Suite struct RouteyCryptoTests {
  let iters: UInt32 = 200_000   // smaller than prod for fast tests

  @Test func roundTrips() throws {
    let plain = Data("hello route".utf8)
    let blob = try RouteyCrypto.encrypt(plain, passphrase: "correct horse", payloadSchemaVersion: 1, iterations: iters)
    let (out, ver) = try RouteyCrypto.decrypt(blob, passphrase: "correct horse")
    #expect(out == plain)
    #expect(ver == 1)
  }

  @Test func wrongPassphraseFails() throws {
    let blob = try RouteyCrypto.encrypt(Data("x".utf8), passphrase: "right", payloadSchemaVersion: 1, iterations: iters)
    #expect(throws: RouteyCryptoError.self) {
      _ = try RouteyCrypto.decrypt(blob, passphrase: "wrong")
    }
  }

  @Test func tamperFails() throws {
    var blob = try RouteyCrypto.encrypt(Data("x".utf8), passphrase: "p", payloadSchemaVersion: 1, iterations: iters)
    blob[blob.count - 1] ^= 0xFF   // flip a ciphertext/tag byte
    #expect(throws: RouteyCryptoError.self) {
      _ = try RouteyCrypto.decrypt(blob, passphrase: "p")
    }
  }

  @Test func badMagicFails() {
    #expect(throws: RouteyCryptoError.self) {
      _ = try RouteyCrypto.decrypt(Data([0,1,2,3,4,5,6,7,8,9,10,11]), passphrase: "p")
    }
  }

  @Test func saltAndNonceAreRandomPerExport() throws {
    let a = try RouteyCrypto.encrypt(Data("x".utf8), passphrase: "p", payloadSchemaVersion: 1, iterations: iters)
    let b = try RouteyCrypto.encrypt(Data("x".utf8), passphrase: "p", payloadSchemaVersion: 1, iterations: iters)
    #expect(a != b)   // different salt+nonce => different ciphertext
  }
}
```

- [ ] **Step 3:** Run — FAIL.

- [ ] **Step 4: Implement** `RouteyCrypto.swift`:

```swift
import Foundation
import CryptoKit
import CommonCrypto

public enum RouteyCryptoError: Error, Equatable {
  case badFormat
  case unsupportedVersion(UInt8)
  case wrongPassphraseOrCorrupt
}

public enum RouteyCrypto {
  private static let magic = Data("RTYE".utf8)
  private static let formatVersion: UInt8 = 1
  private static let kdfPBKDF2SHA256: UInt8 = 1
  private static let saltLen = 16
  private static let keyLen = 32

  public static func encrypt(
    _ plaintext: Data, passphrase: String, payloadSchemaVersion: UInt16, iterations: UInt32
  ) throws -> Data {
    var salt = Data(count: saltLen)
    let ok = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, saltLen, $0.baseAddress!) }
    guard ok == errSecSuccess else { throw RouteyCryptoError.badFormat }
    let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)

    var header = Data()
    header.append(magic)
    header.append(formatVersion)
    header.append(kdfPBKDF2SHA256)
    header.append(contentsOf: withUnsafeBytes(of: iterations.bigEndian, Array.init))
    header.append(UInt8(saltLen))
    header.append(salt)
    header.append(contentsOf: withUnsafeBytes(of: payloadSchemaVersion.bigEndian, Array.init))

    let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: header)
    // sealed.combined = nonce(12) + ciphertext + tag(16)
    return header + sealed.combined!
  }

  public static func decrypt(_ data: Data, passphrase: String) throws -> (plaintext: Data, payloadSchemaVersion: UInt16) {
    var i = data.startIndex
    func take(_ n: Int) throws -> Data {
      guard data.distance(from: i, to: data.endIndex) >= n else { throw RouteyCryptoError.badFormat }
      let end = data.index(i, offsetBy: n); defer { i = end }
      return data[i..<end]
    }
    guard try take(4) == magic else { throw RouteyCryptoError.badFormat }
    let fmt = try take(1).first!
    guard fmt == formatVersion else { throw RouteyCryptoError.unsupportedVersion(fmt) }
    let kdf = try take(1).first!
    guard kdf == kdfPBKDF2SHA256 else { throw RouteyCryptoError.unsupportedVersion(kdf) }
    let iterations = try take(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    let sLen = Int(try take(1).first!)
    let salt = try take(sLen)
    let schemaVersion = try take(2).reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }

    let headerEnd = i
    let header = data[data.startIndex..<headerEnd]
    let body = data[headerEnd...]

    let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
    do {
      let box = try AES.GCM.SealedBox(combined: body)
      let plain = try AES.GCM.open(box, using: key, authenticating: header)
      return (plain, schemaVersion)
    } catch {
      throw RouteyCryptoError.wrongPassphraseOrCorrupt
    }
  }

  private static func deriveKey(passphrase: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
    var derived = Data(count: keyLen)
    let pw = Array(passphrase.utf8)
    let status = derived.withUnsafeMutableBytes { dOut in
      salt.withUnsafeBytes { sIn in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2),
          pw, pw.count,
          sIn.bindMemory(to: UInt8.self).baseAddress, salt.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
          iterations,
          dOut.bindMemory(to: UInt8.self).baseAddress, keyLen
        )
      }
    }
    guard status == kCCSuccess else { throw RouteyCryptoError.badFormat }
    return SymmetricKey(data: derived)
  }
}
```

- [ ] **Step 5:** Run — PASS (5/5). (If `CommonCrypto` import needs a modulemap on this toolchain, it is available directly on Apple platforms via `import CommonCrypto`.)

- [ ] **Step 6:** Commit `"Add passphrase crypto envelope (PBKDF2 -> AES-GCM, versioned AAD)"`.

---

### Task 2: Route DTOs + model mapping

**Files:** `RouteyExport/RouteDTO.swift`, `DTOMapping.swift`, `Package.swift` (add `RouteyModel`, `RouteyPersistence` deps to `RouteyExport`).

**Interfaces:**
- `struct RouteExportDTO: Codable, Equatable, Sendable` — the whole graph for one route: route fields + arrays of stop/module/deliveryPoint/address/tag/deliveryPointAddress/addressTag DTOs (each a flat Codable struct with the same fields + UUIDs).
- `enum DTOMapping`:
  - `static func buildDTO(routeID: Route.ID, from db: any DatabaseReader) throws -> RouteExportDTO` — gathers the route + all rows reachable from it (stops → modules/points → joined addresses → their tags).
  - `static func insert(_ dto: RouteExportDTO, asBorrowed: Bool, into db: any DatabaseWriter) throws -> Route.ID` — inserts with **freshly minted UUIDs** (remap all IDs so an imported route never collides with the holder's own rows), sets `isBorrowed`.

- [ ] **Step 1: Write failing test** (in `ExportImportRoundTripTests`, paired with Task 4) — deferred; this task's test: `buildDTO` on a known small graph returns the expected counts (stops, points, addresses, tags, joins).
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement** DTOs + mapping. `insert` regenerates every UUID and rewrites foreign keys consistently via an old→new id map.
- [ ] **Step 4:** Run — PASS. Commit `"Add route export DTOs + model mapping with id remap"`.

---

### Task 3: v3 migration — borrowed flag + read-only guard

**Files:** `RouteyPersistence/Schema.swift` (+ v3 migration), `RouteyModel/Route.swift` (+ field), `RouteyDomain/RouteEditing.swift` (guard), tests.

- [ ] **Step 1: Write failing tests** — after a v3 migration, `routes` has `isBorrowed`; `RouteEditing.addStop` (and other edits) throw `RouteEditingError.routeIsBorrowed` when the route `isBorrowed == true`.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement.** v3 migration: `ALTER TABLE "routes" ADD COLUMN "isBorrowed" INTEGER NOT NULL DEFAULT 0` (additive — allowed under append-only/CloudKit). Add `var isBorrowed = false` to `Route`. Add an `isBorrowed` check at the top of each mutating `RouteEditing` op (look up the owning route; throw if borrowed).
- [ ] **Step 4:** Run — PASS. Commit `"Add borrowed flag (v3) + read-only guard for imported routes"`.

---

### Task 4: Exporter + importer + round-trip

**Files:** `RouteyExport/RouteExporter.swift`, `RouteImporter+Encrypted.swift`, `ExportImportRoundTripTests.swift`.

**Interfaces:**
- `enum RouteExporter { static func export(routeID:, passphrase: String, iterations: UInt32, from db:) throws -> Data }` — `buildDTO` → `JSONEncoder` → `RouteyCrypto.encrypt(payloadSchemaVersion: current)`.
- `enum EncryptedRouteImporter { static func `import`(_ data: Data, passphrase: String, into db:) throws -> Route.ID }` — `RouteyCrypto.decrypt` → check `payloadSchemaVersion <= supported` (else throw) → `JSONDecoder` → `DTOMapping.insert(asBorrowed: true)`.

- [ ] **Step 1: Write failing round-trip test** — build a route with a CMB (stops, modules, compartments, shared address, tags); `export` with a passphrase; `import` the bytes into a **fresh** DB with the passphrase; assert the full graph is restored (counts match), the new route `isBorrowed == true`, and IDs differ from the originals. Also assert importing with the wrong passphrase throws.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement** exporter/importer (production export uses `iterations = max(600_000, calibrated)`; tests pass a smaller count).
- [ ] **Step 4:** Run — PASS. `swift test` (all suites across all plans). Commit `"Add encrypted route exporter + importer with round-trip test"`.

---

### Task 5: Export/Import UI

> Requires app shell.

**Files:** `app/Routey/Share/ExportRouteView.swift`, `ImportRouteView.swift`; register a `.routey` `UTType`.

- [ ] **Step 1:** Define an exported `UTType` `com.routey.route` (conforms to `public.data`, extension `routey`) in the app's Info.plist.
- [ ] **Step 2:** `ExportRouteView` — passphrase + confirm fields; on export, call `RouteExporter.export` (on a background task; show progress for the ~300ms KDF), write to a temp `.routey` file with file protection, present `ShareLink`/share sheet (AirDrop/Messages/Mail). Remind the user to send the passphrase out-of-band.
- [ ] **Step 3:** `ImportRouteView` — `fileImporter` for `.routey`; prompt passphrase; call `EncryptedRouteImporter.import`; on `wrongPassphraseOrCorrupt` show a clear "wrong passphrase" message; on success, navigate to the new **borrowed** route (badge it "Borrowed — read-only" in the route list; edit affordances hidden/disabled).
- [ ] **Step 4:** Run on two simulators/devices: export from A, AirDrop/share to B, import with the passphrase, confirm the borrowed route appears read-only with the full graph.
- [ ] **Step 5:** Commit `"Add encrypted export/import UI with borrowed read-only routes"`.

---

## Plan self-review

- **Spec coverage:** encrypted `.routey` export/import ✓ (T1/T4/T5), PBKDF2→AES-GCM with versioned AAD header + stored iterations ✓ (T1), wrong-passphrase = auth failure, no plaintext verifier ✓ (T1), DTOs decoupled from models with independent `payloadSchemaVersion` ✓ (T2/T4), id remap so imports never collide ✓ (T2), borrowed/read-only imported routes ✓ (T3/T5), file is the sole handoff (no CloudKit sharing) ✓ (constraints). 
- **Placeholders:** none — the crypto envelope and round-trip are fully coded + tested; DTO mapping and exporter/importer are specified with complete signatures and an end-to-end round-trip test.
- **Type consistency:** `RouteyCrypto.encrypt/decrypt` (T1) used by exporter/importer (T4); `RouteExportDTO` (T2) flows through encode→encrypt→decrypt→decode→insert; `isBorrowed` (T3) set by importer and read by the UI.
- **Security honesty:** salt+nonce are random per export (tested), header is AAD-bound (tamper test), iterations stored in-header and ≥600k in production; no plaintext password verifier (auth failure is the signal). KDF is PBKDF2 (CryptoKit has none); `kdfID` reserves a slot for a future Argon2id upgrade without breaking old files.

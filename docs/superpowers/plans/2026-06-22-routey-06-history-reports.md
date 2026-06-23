# Routey Plan 06 — History & Reports

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make every past delivery searchable ("Delivery Intelligence"), and let the carrier **print their own current tie-out sheet, case strips, and filtered lists** — the artifacts that are otherwise hard to keep updated.

**Architecture:** `RouteyDomain` gains history archival + filtered queries over `deliveryRecords`. A pure `ReportBuilder` produces structured `Report` values (title + columns + rows) — testable headlessly — which the iOS app renders to PDF (`UIGraphicsPDFRenderer`) for AirPrint/share. Report *content* is engine-agnostic and unit-tested; only rendering is app-level.

**Tech Stack:** Swift 6, SwiftUI, SQLiteData/GRDB, UIKit (PDF render, iOS only), Swift Testing.

**Depends on:** Plan 01 (model), Plan 05 (`DeliveryRecord`, `TodaysRun`), Plan 03 (`SearchIndex` for address-based history search). UI requires app shell.

## Global Constraints

- Inherited from Plan 01. **Reports are public-adjacent but internal to the carrier** — they may show route data; they are not marketing surfaces, so postal terms are fine.
- Report *content* (rows/columns) lives in `RouteyDomain` and is unit-tested; PDF *rendering* lives in the app (iOS) — keep them separate so content is testable on macOS.
- History queries are read-only and offline.

---

## File structure

```
RouteyKit/Sources/RouteyDomain/
  History.swift                        # archival + filtered delivery-record queries
  ReportBuilder.swift                  # Report value types + builders (tie-out, case strips, filtered list)
RouteyKit/Tests/RouteyDomainTests/
  HistoryTests.swift
  ReportBuilderTests.swift
app/Routey/History/
  HistoryView.swift                    # searchable delivery history + filters
  ReportsView.swift                    # pick report -> preview -> print/share
  PDFRenderer.swift                    # Report -> PDF Data (UIKit)
```

---

### Task 1: History archival + filtered queries

**Files:** `RouteyDomain/History.swift`, `HistoryTests.swift`.

**Interfaces:**
- `enum History`:
  - `static func archive(runID: TodaysRun.ID, at: Date, in db:) throws` — sets `todaysRuns.archivedAt`.
  - `struct HistoryFilter: Sendable { var dateFrom: Date?; var dateTo: Date?; var outcome: String?; var tagName: String?; var hasPhoto: Bool? }`
  - `static func records(matching: HistoryFilter, in db: any DatabaseReader) throws -> [DeliveryRecord]` — applies the filters (tag via join `addressTags→tags`; `hasPhoto` via `photoPath IS NOT NULL`).

- [ ] **Step 1: Write failing tests** — seed a run with delivery records (one `safedrop` with photo, one `notHomeCarded` no photo, one address tagged `dog`); assert `records(outcome:"safedrop")` returns 1, `hasPhoto:true` returns 1, `tagName:"dog"` returns the tagged one, date-range filtering works.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement** with typed queries/joins; pass dates in (no `Date()` in logic).
- [ ] **Step 4:** Run — PASS. Commit `"Add history archival + filtered delivery queries"`.

---

### Task 2: Address-based history search

**Files:** extend `History.swift`, `HistoryTests.swift`.

**Interfaces:**
- `static func records(forAddressQuery q: String, in db:) throws -> [DeliveryRecord]` — uses `SearchIndex.match(q)` to resolve address IDs, then returns their delivery records (most recent first). Answers "did I deliver to 1284, and when?"

- [ ] **Step 1: Write failing test** — deliver to "1284 Concession Rd 6", then `records(forAddressQuery:"128")` returns that record.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement** (RouteyDomain already depends on RouteySearch transitively via the app; add the dep if needed).
- [ ] **Step 4:** Run — PASS. Commit `"Add address-based history search"`.

---

### Task 3: ReportBuilder (pure content)

**Files:** `RouteyDomain/ReportBuilder.swift`, `ReportBuilderTests.swift`.

**Interfaces:**
- `struct Report: Equatable, Sendable { var title: String; var columns: [String]; var rows: [[String]] }`
- `enum ReportBuilder`:
  - `static func tieOutSheet(routeID:, in db:) throws -> Report` — columns `["Tie-out","Civic","Street","Site/Compartment","Tags"]`, one row per delivery point in route order (mirrors the official sheet layout).
  - `static func caseStrips(routeID:, in db:) throws -> Report` — rows of slot labels (civic(s) + tie-out) in case order, grouped for printing onto strips.
  - `static func filteredList(routeID:, tagName: String?, deliveredOn: Date?, in db:) throws -> Report` — e.g. all `no-flyers` addresses, or parcels delivered on a date.

- [ ] **Step 1: Write failing tests** — build a small route + a CMB; assert `tieOutSheet` has the right column headers and a row per delivery point in `sortIndex` order with the compartment locator filled; `filteredList(tagName:"no-flyers")` returns only tagged addresses; `caseStrips` lists civic+tie-out per slot incl. shared civics.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3: Implement** (pure queries → `Report` rows; no rendering).
- [ ] **Step 4:** Run — PASS. `swift test` (all). Commit `"Add ReportBuilder (tie-out sheet, case strips, filtered lists)"`.

---

### Task 4: PDF rendering + print/share (UI)

> Requires app shell.

**Files:** `app/Routey/History/PDFRenderer.swift`.

**Interfaces:**
- `enum PDFRenderer { static func render(_ report: Report, pageSize: CGSize = .init(width: 612, height: 792)) -> Data }` — `UIGraphicsPDFRenderer` draws the title, column headers, and rows with pagination; returns PDF `Data`.

- [ ] **Step 1:** Implement the renderer (paginate rows; monospaced columns; repeat headers per page). 
- [ ] **Step 2:** Lightweight check in an iOS test target (or manual): render a multi-row `Report`, assert the `Data` is a valid non-empty PDF (`%PDF` header) with >0 pages. Manual: open in Quick Look / print preview.
- [ ] **Step 3:** Commit `"Add PDF renderer for reports"`.

---

### Task 5: History & Reports screens (UI)

> Requires app shell.

**Files:** `app/Routey/History/HistoryView.swift`, `ReportsView.swift`.

- [ ] **Step 1:** `HistoryView` — searchable list of delivery records (by address via Task 2; filter chips for outcome / tag / has-photo via Task 1); tapping a record shows outcome, time, GPS, and the photo if present.
- [ ] **Step 2:** `ReportsView` — pick a report (tie-out sheet / case strips / filtered list with a tag or date picker) → preview the `Report` table → **Print** (`UIPrintInteractionController` with the PDF) or **Share** (`ShareLink` with the PDF `Data` as a `.routey`-adjacent `.pdf`).
- [ ] **Step 3:** Run in simulator; generate a tie-out sheet PDF and a no-flyers list; verify print preview + share sheet.
- [ ] **Step 4:** Commit `"Add history + reports screens with print/share"`.

---

## Plan self-review

- **Spec coverage:** searchable delivery history incl. by-address and by-photo ✓ (T1–T2), flag/outcome/date filters ✓ (T1), print tie-out sheet ✓ (T3–T5), print **case strips** ✓ (T3–T5), print filtered lists (no-flyers, delivered-on-date) ✓ (T3–T5), archival ✓ (T1). 
- **Placeholders:** none — history/report content fully coded + tested; only PDF rendering is app-level with a validity check.
- **Type consistency:** `HistoryFilter`/`Report` defined once and consumed by the UI; `ReportBuilder` outputs feed `PDFRenderer.render` verbatim.
- **Testability honesty:** report *content* is unit-tested on macOS; PDF *rendering* (UIKit) is validated by a PDF-header/page check + manual print preview, since `UIGraphicsPDFRenderer` is iOS-only.

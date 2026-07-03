# Airplane-Mode Smoke Checklist

Use this on Dan's physical iPhone for the V1.0 internal field cut. All sample
data below is fake and must stay fake.

## Fake Route Sample

Paste this into Routey's route import text field:

```csv
civic,street,tieout,occupant,notes
101,Example Ridge Road,Case A,Alex Example,Parcel shelf marker
118,Example Ridge Road,Case A,Jordan Sample,Shared roadside box
202,Sample Cove Drive,Case B,Taylor Placeholder,Door delivery note
44,Demo Orchard Lane,Case C,Morgan Fixture,Oversize parcel
```

Use this fake label text for Snap-to-Add, either printed large or displayed on a
second screen:

```text
Taylor Placeholder
202 Sample Cove Drive
Demo County
SIGNATURE
```

## Checklist

- [ ] Install the latest internal TestFlight build while online.
  Expected result: Routey is installed on the iPhone and can launch from the Home Screen.

- [ ] Enable Airplane Mode, confirm Wi-Fi and cellular are off, then launch Routey.
  Expected result: The app launches without waiting for network or sync.

- [ ] Open Routes, start an import, name it `Fake Smoke Loop`, and paste the fake route sample.
  Expected result: The import preview shows 4 stops and 0 skipped rows.

- [ ] Tap Import.
  Expected result: `Fake Smoke Loop` appears in Routes without network access.

- [ ] Open Search and search for `202`.
  Expected result: `202 Sample Cove Drive` appears with locator details.

- [ ] Open Snap-to-Add and scan the fake label text.
  Expected result: Routey suggests or adds `202 Sample Cove Drive`; no network prompt or spinner is required.

- [ ] Open Run and confirm today's run exists for `Fake Smoke Loop`.
  Expected result: The run board lists the fake stops in delivery order.

- [ ] Check off the first stop.
  Expected result: Progress increments and the checked stop remains visually done.

- [ ] Use "Done through here" on the second or third stop.
  Expected result: All stops up to that point become done; later stops remain undone.

- [ ] Drag reorder one remaining stop.
  Expected result: The row moves, and the run stays usable after the move.

- [ ] Force-quit Routey, keep Airplane Mode on, and relaunch.
  Expected result: `Fake Smoke Loop`, today's run progress, and the reordered stop order persist locally.

- [ ] Turn Airplane Mode off only after the offline checklist is complete.
  Expected result: Sync may resume in the background, but the completed smoke result did not depend on network access.

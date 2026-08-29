# Routey App Store Next Steps

Status as of July 12, 2026: Routey has a working scheduled internal TestFlight
lane. The `nightly` release-train runs `29148775636` and `29188738829` built,
processed, and internally distributed `0.1 (7)` and `0.1 (8)`. That does not
make the app App Store-ready; it proves scheduled resolution plus the
upload/processing/distribution path.

## Next Ten Steps

1. **Prove the V1.0 phone workflow.** Keep the first cut to import/editing,
   predictive search, Snap-to-Add, and Today's Run check-off, done-through-here,
   stop detail, and drag reorder. Fix defects exposed by the field smoke without
   pulling V1.1 UI into the release gate.
2. **Run the release smoke on device.** Test an invented route in airplane mode:
   import/edit -> search -> generate Today's Run -> snap a label -> check off,
   done-through-here, inspect stop detail, and reorder. Record failures as
   issues.
3. **Deploy and prove Production CloudKit.** Promote the private database schema
   to Production, then test production-signed builds on devices. Keep local
   SQLite as source of truth and verify sync never blocks core UI.
4. **Finish App Store privacy work.** Generate the Xcode aggregate privacy
   report, verify `PrivacyInfo.xcprivacy` coverage if required, confirm camera
   and CloudKit disclosures, and ensure the privacy policy matches the shipping
   build rather than future planned features.
5. **Complete App Store Connect metadata.** Confirm app name, subtitle,
   description, keywords, category, copyright, support URL, marketing URL,
   privacy URL, review contact, review notes, and "What to Test" text.
6. **Create screenshot and preview assets.** Capture current iPhone/iPad
   screenshots with invented placeholder data only. Avoid watchOS or CarPlay
   screenshots until those products exist.
7. **Complete compliance questionnaires.** Fill in age rating, export
   compliance, content rights, EU DSA trader status, and accessibility nutrition
   labels. Run an accessibility pass before declaring support.
8. **Confirm pricing and the free-vs-paid boundary.** Revalidate the current
   business decision in its source of truth before locking App Store copy or
   campaigns.
9. **Run a submission rehearsal.** Use fastlane validation, Xcode archive
   validation, and an internal TestFlight build with final metadata. Confirm
   App Store Connect shows the build as processed and selectable.
10. **Prepare first review submission.** Select the final build, attach review
    notes, verify no placeholders or real route data exist in screenshots/docs,
    and submit only after the smoke log, privacy answers, metadata, and assets
    are final.

Delivery-outcome logging, Today's Run filters, follow-up UI, history/report UI,
PDF/print/share, encrypted `.routey` handoff UI, and watchOS remain on the V1.1
roadmap; they are not prerequisites for the V1.0 field cut.

## Submission Checklist

- [ ] `cd RouteyKit && swift test` green.
- [ ] iOS app and `RouteyMacProof` compile in CI.
- [ ] Physical-device smoke log completed with invented data.
- [ ] Production CloudKit schema deployed and tested.
- [ ] Privacy policy and App Store privacy answers match the build.
- [ ] Accessibility nutrition labels reviewed against actual behavior.
- [ ] Screenshots show current app UI and invented placeholder data only.
- [ ] App Store icon has required sizes and no alpha issues.
- [ ] Export compliance remains `ITSAppUsesNonExemptEncryption = false`, or
  documentation is updated before upload if that changes.
- [ ] Review notes explain offline-first behavior, private CloudKit sync, and
  any non-obvious flows.

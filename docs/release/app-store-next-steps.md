# Routey App Store Next Steps

Status as of July 1, 2026: Routey has a working internal TestFlight lane. The
manual `nightly` release-train run `28495461531` built and processed `0.1 (4)`
and fastlane reported that it distributed the build to internal testers. That
does not make the app App Store-ready; it proves the upload/distribution path.

## Next Ten Steps

1. **Finish the V1.0 phone workflow.** Close the remaining user-facing gaps:
   proof-of-delivery/outcome logging UI, run filters, PDF/print/share, and
   encrypted `.routey` file import/export UI.
2. **Run the release smoke on device.** Test an invented route in airplane mode:
   import/edit -> search -> generate Today's Run -> snap a label -> deliver/log
   outcomes -> history/report -> export/import. Record failures as issues.
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
8. **Decide pricing and free-vs-paid boundary.** Kickstart still tracks pricing
   and free/paid decisions for July 7, so do not lock App Store copy or
   campaigns until that product decision is made.
9. **Run a submission rehearsal.** Use fastlane validation, Xcode archive
   validation, and an internal TestFlight build with final metadata. Confirm
   App Store Connect shows the build as processed and selectable.
10. **Prepare first review submission.** Select the final build, attach review
    notes, verify no placeholders or real route data exist in screenshots/docs,
    and submit only after the smoke log, privacy answers, metadata, and assets
    are final.

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

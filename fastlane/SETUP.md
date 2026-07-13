# Fastlane Setup

Routey's fastlane setup keeps App Store Connect credentials out of git and uses
checked-in metadata files as the source of truth for App Store and TestFlight
text:

- `fastlane/metadata/en-US/*.txt` for App Store product-page metadata.
- `fastlane/testflight/en-US/*.txt` for TestFlight beta description and "What
  to Test" text.

## Credentials

1. Create or copy an App Store Connect API key JSON file.
2. Put it at `fastlane/api_key.json`, or copy `fastlane/.env.example` to
   `fastlane/.env` and set `APP_STORE_CONNECT_API_KEY_JSON_PATH`.
3. For `.p8`-style setup, put the key at `fastlane/AuthKey_<KEY_ID>.p8` and
   fill in the `APP_STORE_CONNECT_API_KEY_*` values in `fastlane/.env`.
4. Set `MATCH_PASSWORD` in `fastlane/.env` so fastlane can decrypt the shared
   signing repository configured in `fastlane/Matchfile`.

Never commit `.env`, `api_key.json`, `.p8` files, or App Review contact files.
`.gitignore` excludes all of them.

GitHub Actions uploads also require repository secrets named
`APP_STORE_CONNECT_API_KEY_JSON`, `MATCH_PASSWORD`, and `MATCH_GIT_SSH_KEY`.
`TESTFLIGHT_FEEDBACK_EMAIL` is optional but should be set before wider beta
testing. `TESTFLIGHT_MARKETING_URL` and `TESTFLIGHT_PRIVACY_POLICY_URL` can be
set as repository variables when the checked-in metadata should be overridden.

## Commands

Run these from the repository root:

```sh
fastlane ios validate_metadata
fastlane ios validate_testflight_metadata
fastlane ios metadata
fastlane ios testflight_metadata
fastlane ios beta channel:nightly
```

`validate_metadata` checks the local text files against App Store character
limits. `validate_testflight_metadata` checks the beta description and What to
Test text before an upload tries to touch App Store Connect.

`metadata` uploads only App Store metadata; it skips binary upload, screenshots,
and review submission. `testflight_metadata` updates TestFlight metadata for an
already uploaded build. `beta channel:nightly` builds, uploads, waits for
processing, and distributes to internal testers when the required signing and
App Store Connect secrets are available.

## Current Release Proof

On July 1, 2026, GitHub Actions run `28495461531` manually dispatched the
`nightly` release train. It built Routey `0.1 (4)`, waited for processing, and
fastlane reported successful distribution to internal testers. Treat that as
proof of the internal TestFlight lane only; App Store review still needs final
screenshots, privacy/compliance metadata, Production CloudKit validation, and
device smoke evidence.

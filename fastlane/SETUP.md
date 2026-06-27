# Fastlane Setup

Routey's fastlane setup keeps App Store Connect credentials out of git and uses
`fastlane/metadata/en-US/*.txt` as the source of truth for App Store fields.

## Credentials

1. Create or copy an App Store Connect API key JSON file.
2. Put it at `fastlane/api_key.json`, or copy `fastlane/.env.example` to
   `fastlane/.env` and set `APP_STORE_CONNECT_API_KEY_JSON_PATH`.
3. For `.p8`-style setup, put the key at `fastlane/AuthKey_<KEY_ID>.p8` and
   fill in the `APP_STORE_CONNECT_API_KEY_*` values in `fastlane/.env`.

Never commit `.env`, `api_key.json`, `.p8` files, or App Review contact files.
`.gitignore` excludes all of them.

## Commands

Run these from the repository root:

```sh
fastlane ios validate_metadata
fastlane ios metadata
```

`validate_metadata` checks the local text files against App Store character
limits. `metadata` uploads only the metadata files; it skips binary upload,
screenshots, and review submission.

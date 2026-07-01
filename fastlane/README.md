fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios validate_metadata

```sh
[bundle exec] fastlane ios validate_metadata
```

Validate App Store metadata text files locally

### ios validate_testflight_metadata

```sh
[bundle exec] fastlane ios validate_testflight_metadata
```

Validate TestFlight metadata text files locally

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload App Store metadata from fastlane/metadata

### ios testflight_metadata

```sh
[bundle exec] fastlane ios testflight_metadata
```

Update TestFlight metadata for an already-uploaded Routey build

### ios build

```sh
[bundle exec] fastlane ios build
```

Build an App Store archive for Routey

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload Routey to TestFlight

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).

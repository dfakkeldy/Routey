# Routey App Icon Source

This folder preserves a carrier-agnostic candidate redesign for the Routey app
icon. It differs from the icon currently shipped in `Assets.xcassets` and is not
wired into the app target.

- `RouteyAppIcon.icon` is an Icon Composer package with background, route, and
  stop layers.
- `RouteyAppIcon-composite.svg` is a single-file SVG preview/fallback.
- `RouteyAppIcon.sketch` is the editable Sketch source when regenerated through
  Sketch MCP.
- `previews/default.png` and `previews/tinted-dark.png` are Icon Composer CLI
  renders for quick review.

The preserved previews were rendered with Xcode 26.6 (build 17F113). The exact
`ictool` invocation was not captured with the orphaned source, so regenerate and
document fresh previews before adopting this design as the production icon.

The artwork avoids employer names, real route data, street/site names, civic
numbers, and carrier-specific marks.

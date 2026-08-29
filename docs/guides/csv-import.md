# CSV route import

Routey accepts a simple comma-separated file whose first nonblank row contains
a `street` header. Values cannot contain embedded commas or CSV quotes.

## Columns

| Column | Purpose |
| --- | --- |
| `tieOut` | Drive-order label shown on the stop. |
| `civic` | Civic number. |
| `street` | Street name; the only required header. |
| `occupant` | Optional occupant name. |
| `postalCode` | Optional postal code. |
| `notes` | Optional route note. |
| `site` | Shared delivery-site name. Rows with the same site share one stop. |
| `module` | Optional module inside a shared site. |
| `compartment` | Optional compartment. Rows with the same site, module, and compartment share one delivery point. |
| `tags` | Semicolon- or pipe-separated nonwarning tags. |
| `warnings` | Semicolon- or pipe-separated warning tags. |

Headers are case-insensitive. Spaces, underscores, and hyphens in header names
are ignored. Unknown columns are ignored.

## Example

```csv
tieOut,civic,street,site,module,compartment,tags,warnings
10,10100,County Rd 12,,,,no-flyers,dog
11A,3400,County Rd 12,Community Boxes,5,7,,
11A,3402,County Rd 12,Community Boxes,5,7,,
```

The first row imports as a roadside point. The last two addresses share the
same site, module, and compartment. Import order becomes the route's initial
stop order; it can be edited later in Routey.

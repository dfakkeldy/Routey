# Routey — Future Updates (backlog)

Ideas captured for *after* V1.0. Not scheduled; not in any current plan. Each entry notes
the problem, the idea, the hard parts, and what it would build on.

---

## Parcel compartment fit prediction ("will it fit?")

**Problem.** Parcel compartments at community-mailbox sites aren't all the same size, and a
carrier can't reliably tell at the depot whether a given package will fit — or even remember
whether a particular site *has* a larger parcel compartment. The result is wasted trips and
last-minute carding.

**Idea.** Let Routey predict, before leaving the depot, whether a parcel will fit an available
compartment at its destination site:
- **Record compartment inventory per site/module** — for each `DeliveryPoint` of kind
  `compartment`, capture a size class (or measured W×H×D) and whether the site has an
  oversize/parcel-locker compartment. (Extends the existing Delivery-Point model with size
  attributes; `isParcelLocker` already exists.)
- **Capture package size at sort time** — a quick size-class pick, or measure with the camera
  (ARKit object dimensioning / LiDAR on Pro devices) during the Snap-to-Add flow.
- **Predict fit** — compare the package's dimensions to the destination site's available
  compartment sizes and warn early: "won't fit — plan to card it" or "fits the Module 2
  oversize locker."

**Hard parts.**
- Getting accurate compartment dimensions (a one-time measure-per-site setup; tedious).
- Reliable package measurement (LiDAR helps on newer Pro devices; needs a manual fallback).
- Availability is dynamic — a compartment may already be occupied that day.

**Builds on.** The Delivery-Point model (add size attributes), the Snap-to-Add flow
(add parcel-size capture), and per-site roll-ups.

---

<!-- Add future ideas below this line. -->

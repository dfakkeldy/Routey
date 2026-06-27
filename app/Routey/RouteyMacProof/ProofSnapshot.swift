struct ProofSnapshot: Sendable {
  var counts: ProofCounts
  var routeNames: [String]
  var proofStopOrder: [String]
}

import SwiftUI

struct ProofRouteList: View {
  let routeNames: [String]
  let proofStopOrder: [String]

  var body: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading) {
        Text("Routes")
          .bold()
        List(routeNames, id: \.self) { name in
          Text(name.isEmpty ? "Untitled route" : name)
        }
      }

      VStack(alignment: .leading) {
        Text("Latest proof stop order")
          .bold()
        List(proofStopOrder, id: \.self) { name in
          Text(name.isEmpty ? "Untitled stop" : name)
        }
      }
    }
  }
}

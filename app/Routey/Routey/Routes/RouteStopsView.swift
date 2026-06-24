import SQLiteData
import SwiftUI
import RouteyModel

struct RouteStopsView: View {
  let route: Route
  @FetchAll private var stops: [Stop]
  @State private var filter = ""

  init(route: Route) {
    self.route = route
    _stops = FetchAll(
      Stop
        .where { $0.routeID.eq(#bind(route.id)) }
        .order { $0.sortIndex }
    )
  }

  var body: some View {
    List {
      ForEach(filtered(stops)) { stop in
        StopRowView(stop: stop)
      }
    }
    .navigationTitle(route.name.isEmpty ? "Route" : route.name)
    .searchable(text: $filter, prompt: "Filter stops")
  }

  private func filtered(_ stops: [Stop]) -> [Stop] {
    guard !filter.isEmpty else { return stops }

    return stops.filter { stop in
      stop.displayName.localizedStandardContains(filter)
        || stop.tieOut.localizedStandardContains(filter)
    }
  }
}

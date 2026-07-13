import RouteyDomain
import RouteyModel

nonisolated enum RunRouteSelection {
  static func preferredRouteID(
    in routes: [Route],
    current: Route.ID?
  ) -> Route.ID? {
    if let current, routes.contains(where: { $0.id == current }) {
      return current
    }

    return routes.first(where: { $0.name != TemporaryRouteBuilder.routeName })?.id
      ?? routes.first?.id
  }
}

nonisolated struct RunLoadContext: Equatable, Hashable {
  let routeID: Route.ID
  let serviceDate: String
}

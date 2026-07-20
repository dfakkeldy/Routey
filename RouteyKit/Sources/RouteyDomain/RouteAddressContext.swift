import RouteyModel

public struct RouteAddressContext: Equatable, Sendable {
  public var address: Address
  public var siteName: String?
  public var moduleName: String?
  public var compartmentLabel: String?
  public var driveOrder: String?
  public var tagNames: [String]
  public var warningTagNames: [String]

  public var hasWarning: Bool {
    !warningTagNames.isEmpty
  }

  public var locator: String {
    [
      siteName,
      moduleName.map { "Module \($0)" },
      compartmentLabel.map { "Compartment \($0)" },
      driveOrder.map { "Drive \($0)" },
    ]
    .compactMap(\.self)
    .joined(separator: " · ")
  }

  public init(
    address: Address,
    siteName: String? = nil,
    moduleName: String? = nil,
    compartmentLabel: String? = nil,
    driveOrder: String? = nil,
    tagNames: [String] = [],
    warningTagNames: [String] = []
  ) {
    self.address = address
    self.siteName = siteName
    self.moduleName = moduleName
    self.compartmentLabel = compartmentLabel
    self.driveOrder = driveOrder
    self.tagNames = tagNames
    self.warningTagNames = warningTagNames
  }
}

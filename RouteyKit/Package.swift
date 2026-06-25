// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RouteyKit",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "RouteyModel", targets: ["RouteyModel"]),
    .library(name: "RouteyPersistence", targets: ["RouteyPersistence"]),
    .library(name: "RouteyImport", targets: ["RouteyImport"]),
    .library(name: "RouteyDomain", targets: ["RouteyDomain"]),
    .library(name: "RouteySearch", targets: ["RouteySearch"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/sqlite-data", exact: "1.6.6"),
  ],
  targets: [
    .target(
      name: "RouteyModel",
      dependencies: [.product(name: "SQLiteData", package: "sqlite-data")]
    ),
    .target(
      name: "RouteyPersistence",
      dependencies: [
        "RouteyModel",
        .product(name: "SQLiteData", package: "sqlite-data"),
      ]
    ),
    .target(name: "RouteyImport"),
    .target(
      name: "RouteyDomain",
      dependencies: [
        "RouteyModel",
        "RouteyImport",
        "RouteySearch",
        .product(name: "SQLiteData", package: "sqlite-data"),
      ]
    ),
    .target(
      name: "RouteySearch",
      dependencies: [
        "RouteyModel",
        .product(name: "SQLiteData", package: "sqlite-data"),
      ]
    ),
    .testTarget(
      name: "RouteyPersistenceTests",
      dependencies: [
        "RouteyModel",
        "RouteyPersistence",
        .product(name: "SQLiteData", package: "sqlite-data"),
      ]
    ),
    .testTarget(
      name: "RouteyImportTests",
      dependencies: ["RouteyImport"]
    ),
    .testTarget(
      name: "RouteyDomainTests",
      dependencies: [
        "RouteyDomain",
        "RouteyImport",
        "RouteyModel",
        "RouteyPersistence",
        "RouteySearch",
        .product(name: "SQLiteData", package: "sqlite-data"),
      ]
    ),
    .testTarget(
      name: "RouteySearchTests",
      dependencies: [
        "RouteyModel",
        "RouteyPersistence",
        "RouteySearch",
        .product(name: "SQLiteData", package: "sqlite-data"),
      ]
    ),
  ]
)

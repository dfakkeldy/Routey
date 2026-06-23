import Foundation
import SQLiteData

public enum Schema {
  public static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif
    migrator.registerMigration("Create v1 tables") { db in
      try #sql("""
        CREATE TABLE "routes" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL DEFAULT '',
          "rtaFSA" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "stops" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "routeID" TEXT NOT NULL REFERENCES "routes"("id") ON DELETE CASCADE,
          "tieOut" TEXT NOT NULL DEFAULT '',
          "sortIndex" REAL NOT NULL DEFAULT 0,
          "kind" TEXT NOT NULL DEFAULT 'pointOfCall',
          "displayName" TEXT NOT NULL DEFAULT '',
          "officialSiteID" TEXT,
          "locationText" TEXT,
          "sharesLocationWith" TEXT,
          "latitude" REAL,
          "longitude" REAL,
          "notes" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "modules" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "stopID" TEXT NOT NULL REFERENCES "stops"("id") ON DELETE CASCADE,
          "name" TEXT NOT NULL DEFAULT '',
          "sortIndex" REAL NOT NULL DEFAULT 0
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "deliveryPoints" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "stopID" TEXT NOT NULL REFERENCES "stops"("id") ON DELETE CASCADE,
          "moduleID" TEXT REFERENCES "modules"("id") ON DELETE SET NULL,
          "kind" TEXT NOT NULL DEFAULT 'roadsideBox',
          "label" TEXT NOT NULL DEFAULT '',
          "isParcelLocker" INTEGER NOT NULL DEFAULT 0,
          "status" TEXT NOT NULL DEFAULT 'active',
          "notes" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "addresses" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "civicNumber" INTEGER,
          "civicRangeFrom" INTEGER,
          "civicRangeTo" INTEGER,
          "suite" TEXT,
          "street" TEXT NOT NULL DEFAULT '',
          "occupantName" TEXT,
          "doorLatitude" REAL,
          "doorLongitude" REAL,
          "postalCode" TEXT,
          "notes" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "deliveryPointAddresses" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "deliveryPointID" TEXT NOT NULL REFERENCES "deliveryPoints"("id") ON DELETE CASCADE,
          "addressID" TEXT NOT NULL REFERENCES "addresses"("id") ON DELETE CASCADE
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "tags" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL DEFAULT '',
          "isWarning" INTEGER NOT NULL DEFAULT 0
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "addressTags" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "addressID" TEXT NOT NULL REFERENCES "addresses"("id") ON DELETE CASCADE,
          "tagID" TEXT NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE
        ) STRICT
        """).execute(db)
    }
    return migrator
  }
}

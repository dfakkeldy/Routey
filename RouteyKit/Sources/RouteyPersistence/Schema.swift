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
    migrator.registerMigration("Create v2 daily tables") { db in
      try #sql("""
        CREATE TABLE "todaysRuns" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "routeID" TEXT NOT NULL REFERENCES "routes"("id") ON DELETE CASCADE,
          "serviceDate" TEXT NOT NULL DEFAULT '',
          "createdAt" TEXT NOT NULL DEFAULT '2001-01-01T00:00:00.000Z',
          "archivedAt" TEXT
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "runStops" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "runID" TEXT NOT NULL REFERENCES "todaysRuns"("id") ON DELETE CASCADE,
          "stopID" TEXT REFERENCES "stops"("id") ON DELETE SET NULL,
          "tieOut" TEXT NOT NULL DEFAULT '',
          "displayName" TEXT NOT NULL DEFAULT '',
          "kind" TEXT NOT NULL DEFAULT 'pointOfCall',
          "sortIndex" REAL NOT NULL DEFAULT 0,
          "isDone" INTEGER NOT NULL DEFAULT 0
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "parcels" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "runID" TEXT NOT NULL REFERENCES "todaysRuns"("id") ON DELETE CASCADE,
          "addressID" TEXT REFERENCES "addresses"("id") ON DELETE SET NULL,
          "source" TEXT NOT NULL DEFAULT 'manual',
          "sizeClass" TEXT NOT NULL DEFAULT '',
          "toDoor" INTEGER NOT NULL DEFAULT 0,
          "requiresSignature" INTEGER NOT NULL DEFAULT 0,
          "isCustoms" INTEGER NOT NULL DEFAULT 0,
          "isDelivered" INTEGER NOT NULL DEFAULT 0,
          "labelSnapshot" TEXT NOT NULL DEFAULT '',
          "trackingCode" TEXT NOT NULL DEFAULT '',
          "trackingSymbology" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "deliveryRecords" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "runID" TEXT NOT NULL REFERENCES "todaysRuns"("id") ON DELETE CASCADE,
          "addressID" TEXT REFERENCES "addresses"("id") ON DELETE SET NULL,
          "parcelID" TEXT REFERENCES "parcels"("id") ON DELETE SET NULL,
          "outcome" TEXT NOT NULL DEFAULT '',
          "latitude" REAL,
          "longitude" REAL,
          "loggedAt" TEXT NOT NULL DEFAULT '2001-01-01T00:00:00.000Z',
          "photoPath" TEXT
        ) STRICT
        """).execute(db)

      try #sql("""
        CREATE TABLE "followUpTasks" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "runID" TEXT NOT NULL REFERENCES "todaysRuns"("id") ON DELETE CASCADE,
          "targetStopID" TEXT REFERENCES "stops"("id") ON DELETE SET NULL,
          "addressID" TEXT REFERENCES "addresses"("id") ON DELETE SET NULL,
          "text" TEXT NOT NULL DEFAULT '',
          "isDone" INTEGER NOT NULL DEFAULT 0
        ) STRICT
        """).execute(db)
    }
    return migrator
  }
}

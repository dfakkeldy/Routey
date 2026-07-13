import Foundation

public enum ServiceDate {
  public static func local(
    for date: Date,
    timeZone: TimeZone = .autoupdatingCurrent
  ) -> String {
    date.formatted(
      Date.ISO8601FormatStyle(timeZone: timeZone)
        .year()
        .month()
        .day()
        .dateSeparator(.dash)
    )
  }
}

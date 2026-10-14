import Foundation

/// Shared JSON coders for the REST API.
///
/// Decoding converts snake_case keys to camelCase. Encoding does NOT use
/// `convertToSnakeCase`, because that strategy also rewrites dictionary keys
/// (a sheet cell `"A1"` would leave as `"a1"`). Request bodies spell their
/// snake_case keys out in explicit `CodingKeys` instead.
enum NemiJSON {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let string = try container.decode(String.self)
            if let date = NemiDateFormat.parse(string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date, got \(string)"
            )
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(NemiDateFormat.string(from: date))
        }
        return encoder
    }
}

/// ISO 8601 parsing that accepts the forms a server realistically sends:
/// with or without fractional seconds, and date-only values for all-day events.
public enum NemiDateFormat {
    public static func parse(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }

        return parseDateOnly(string)
    }

    /// Parses `YYYY-MM-DD` as midnight UTC.
    public static func parseDateOnly(_ string: String) -> Date? {
        guard string.count == 10 else { return nil }
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        dateOnly.timeZone = TimeZone(identifier: "UTC")
        return dateOnly.date(from: string)
    }

    /// Formats as `2026-10-14T09:30:00Z`.
    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Formats as `2026-10-14` in UTC.
    public static func dateOnlyString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

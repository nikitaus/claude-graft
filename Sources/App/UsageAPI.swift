import Foundation

/// Reads a plan's live limits from Anthropic's own endpoint, the one Claude
/// Code uses. Better than the figures a profile writes to disk in every way
/// that matters: exact reset times rather than times worked out from history,
/// and current values even for a profile that is not running.
enum UsageAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    struct Reading: Equatable, Codable {
        /// Nil when the plan has no five-hour window, as Ultra does not.
        var fiveHour: Int?
        var week: Int
        var fiveHourReset: Date?
        var weekReset: Date?
        var plan: String?
        var fable: Int? = nil
        var fableReset: Date? = nil
    }

    enum Failure: LocalizedError {
        /// Carries `Retry-After` when the service sends one, so a caller can
        /// wait exactly as long as it was asked to.
        case http(Int, retryAfter: TimeInterval?)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .http(401, _), .http(403, _):
                return L10n.text("That login was refused. Open the profile once so Claude can renew it.")
            case .http(429, _):
                return L10n.text("Anthropic is rate-limiting usage checks. The last figures stay on screen.")
            case .http(let code, _):
                return L10n.format("The usage service answered %ld.", code)
            case .unreadable:
                return L10n.text("The usage service sent something unexpected.")
            }
        }
    }

    /// Blocking; call it off the main thread.
    static func fetch(token: String, timeout: TimeInterval = 10) throws -> Reading {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))",
                         forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        var payload: Data?
        var response: URLResponse?
        var failure: Error?
        let finished = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, urlResponse, error in
            payload = data
            response = urlResponse
            failure = error
            finished.signal()
        }.resume()
        _ = finished.wait(timeout: .now() + timeout + 5)

        if let failure { throw failure }
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        guard code == 200 else {
            let header = http?.value(forHTTPHeaderField: "Retry-After")
            throw Failure.http(code, retryAfter: header.flatMap(TimeInterval.init))
        }
        let parsed = payload.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        guard let body = parsed as? [String: Any], let reading = reading(from: body) else {
            // "Something unexpected" is all the window can say, and it is all
            // it said to every Ultra account, refused for lacking a window that
            // plan does not have. The shape names what changed; the values are
            // left out, since a log is no place for an account's figures.
            let described: Any = parsed.map { shape(of: $0) } ?? "not JSON"
            Diagnostics.note("usage-unreadable", [
                "bytes": payload?.count ?? 0,
                "contentType": http?.value(forHTTPHeaderField: "Content-Type") ?? "",
                "shape": described,
            ])
            throw Failure.unreadable
        }
        return reading
    }

    /// Separated from the request so the shape of the answer can be tested.
    ///
    /// Either window is enough. The five-hour one used to be required, and a
    /// plan without it — Ultra, which is spent against the week alone — had
    /// every answer refused as unexpected, leaving its figures to come off a
    /// record days or weeks old.
    ///
    /// The week is also in `limits`, as `weekly_all`, beside two dozen other
    /// top-level keys that all came back null for that account. Taking it from
    /// there when `seven_day` is not sent means the next window to go the same
    /// way as `five_hour` does not refuse the answer a second time.
    static func reading(from body: [String: Any]) -> Reading? {
        let session = window(body["five_hour"])
        let weekly = window(body["seven_day"])
            ?? limit(body["limits"]) { $0["kind"] as? String == "weekly_all" }
        guard session != nil || weekly != nil else { return nil }
        let fable = limit(body["limits"]) {
            guard $0["kind"] as? String == "weekly_scoped",
                  let scope = $0["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let name = model["display_name"] as? String
            else { return false }
            return name.localizedCaseInsensitiveContains("fable")
        }
        return Reading(fiveHour: session?.used,
                       week: weekly?.used ?? 0,
                       fiveHourReset: session?.resets,
                       weekReset: weekly?.resets,
                       plan: (body["subscription_type"] as? String)?.capitalized,
                       fable: fable?.used,
                       fableReset: fable?.resets)
    }

    /// Keys and the kind of value under each, nested, with no value itself.
    static func shape(of value: Any, depth: Int = 4) -> Any {
        switch value {
        case let object as [String: Any]:
            guard depth > 0 else { return "object" }
            return object.mapValues { shape(of: $0, depth: depth - 1) }
        case let array as [Any]:
            guard depth > 0, let first = array.first else { return "array of \(array.count)" }
            return [shape(of: first, depth: depth - 1), "\(array.count) items"] as [Any]
        case is NSNull: return "null"
        case is String: return "string"
        case is NSNumber, is Int, is Double, is Bool: return "number"
        default: return String(describing: type(of: value))
        }
    }

    private static func window(_ value: Any?) -> (used: Int, resets: Date?)? {
        guard let object = value as? [String: Any],
              let used = Graft.percentage(object["utilization"])
        else { return nil }
        return (used, date(object["resets_at"]))
    }

    /// An entry in `limits` writes `percent` where the older windows write
    /// `utilization`, and has been seen writing the latter too.
    private static func limit(_ value: Any?,
                              where matches: ([String: Any]) -> Bool) -> (used: Int, resets: Date?)? {
        guard let limits = value as? [[String: Any]],
              let entry = limits.first(where: matches),
              let used = Graft.percentage(entry["percent"])
                ?? Graft.percentage(entry["utilization"])
        else { return nil }
        return (used, date(entry["resets_at"]))
    }

    /// `resets_at` comes back as an ISO timestamp, occasionally as epoch seconds.
    private static func date(_ value: Any?) -> Date? {
        if let text = value as? String {
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text) {
                return parsed
            }
            // The service writes microseconds — `05:00:00.141309+00:00`. Were
            // the formatter to refuse six digits, the countdown would vanish
            // while the figure stayed and nothing would say why, so the
            // fraction is cut to milliseconds and tried once more.
            let milliseconds = text.replacingOccurrences(of: #"(\.[0-9]{3})[0-9]+"#, with: "$1",
                                                         options: .regularExpression)
            return withFraction.date(from: milliseconds)
        }
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
        if let seconds = value as? Int { return Date(timeIntervalSince1970: Double(seconds)) }
        return nil
    }
}

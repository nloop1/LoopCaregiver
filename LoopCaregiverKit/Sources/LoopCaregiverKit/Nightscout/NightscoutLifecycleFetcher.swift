//
//  NightscoutLifecycleFetcher.swift
//  LoopCaregiverKit
//

import CryptoKit
import Foundation

/// Fetches Pod / Sensor lifecycle events directly via Nightscout's `/api/v1/treatments.json`.
///
/// We bypass `NightscoutKit.NightscoutClient.fetchTreatments` here because its
/// `TreatmentType` enum does not include "Site Change", "Pod Change", "Sensor
/// Start" or "Sensor Change" — those entries get dropped at parse time before
/// they reach the caller. The same approach is used by LoopFollow.
///
/// The fetch is isolated from the regular treatments cache: it uses an
/// independent 14-day lookback (Pod can be 80h old, sensor up to 240h) and a
/// 5-minute TTL cache, so the 30-second app refresh cycle does not multiply
/// out into Nightscout traffic.
actor NightscoutLifecycleFetcher {
    private let siteURL: URL
    private let apiSecret: String?
    private let urlSession: URLSession

    private struct CacheEntry {
        let fetchDate: Date
        let status: LifecycleStatus
    }
    private var cache: CacheEntry?

    static let cacheTTL: TimeInterval = 5 * 60
    static let lookback: TimeInterval = -14 * 24 * 3600
    static let maxCount = 200

    init(siteURL: URL, apiSecret: String?, urlSession: URLSession = .shared) {
        self.siteURL = siteURL
        self.apiSecret = apiSecret
        self.urlSession = urlSession
    }

    func fetch() async throws -> LifecycleStatus {
        if let cache, Date().timeIntervalSince(cache.fetchDate) < Self.cacheTTL {
            return cache.status
        }

        let entries = try await fetchTreatmentEntries()
        let status = Self.parseLifecycle(entries: entries)
        self.cache = CacheEntry(fetchDate: Date(), status: status)
        return status
    }

    private func fetchTreatmentEntries() async throws -> [[String: Any]] {
        guard let url = buildURL() else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiSecret, !apiSecret.isEmpty {
            request.setValue(Self.sha1Hex(apiSecret), forHTTPHeaderField: "api-secret")
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LifecycleFetchError.invalidResponse
        }

        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr
    }

    private func buildURL() -> URL? {
        var components = URLComponents()
        components.scheme = siteURL.scheme
        components.host = siteURL.host
        components.port = siteURL.port
        components.path = "/api/v1/treatments.json"

        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let startStr = isoFormatter.string(from: now.addingTimeInterval(Self.lookback))
        let endStr = isoFormatter.string(from: now.addingTimeInterval(60))

        components.queryItems = [
            URLQueryItem(name: "find[eventType][$in][]", value: "Site Change"),
            URLQueryItem(name: "find[eventType][$in][]", value: "Pod Change"),
            URLQueryItem(name: "find[eventType][$in][]", value: "Pump Site Change"),
            URLQueryItem(name: "find[eventType][$in][]", value: "Sensor Start"),
            URLQueryItem(name: "find[eventType][$in][]", value: "Sensor Change"),
            URLQueryItem(name: "find[created_at][$gte]", value: startStr),
            URLQueryItem(name: "find[created_at][$lte]", value: endStr),
            URLQueryItem(name: "count", value: String(Self.maxCount))
        ]

        return components.url
    }

    static func parseLifecycle(entries: [[String: Any]]) -> LifecycleStatus {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFrac = ISO8601DateFormatter()
        withoutFrac.formatOptions = [.withInternetDateTime]

        var latestSensor: Date?
        var latestPod: Date?

        for entry in entries {
            guard let eventType = entry["eventType"] as? String else { continue }
            let createdAtStr = (entry["created_at"] as? String) ?? (entry["timestamp"] as? String)
            guard let createdAtStr,
                  let date = withFrac.date(from: createdAtStr) ?? withoutFrac.date(from: createdAtStr)
            else { continue }

            switch eventType {
            case "Sensor Start", "Sensor Change":
                if latestSensor == nil || date > latestSensor! {
                    latestSensor = date
                }
            case "Site Change", "Pod Change", "Pump Site Change":
                if latestPod == nil || date > latestPod! {
                    latestPod = date
                }
            default:
                break
            }
        }

        return LifecycleStatus(latestSensorStart: latestSensor, latestPodChange: latestPod)
    }

    private static func sha1Hex(_ string: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    enum LifecycleFetchError: Error {
        case invalidResponse
    }
}

import Foundation
import AppKit

// MARK: - 天气（Open-Meteo，免费无 key）

struct WeatherHour: Equatable {
    let label: String
    let temp: Int
    let code: Int
}

struct WeatherNow: Equatable {
    var temp: Int = 0
    var code: Int = 0
    var high: Int = 0
    var low: Int = 0
    var hours: [WeatherHour] = []
    var city: String = ""
}

enum WeatherCode {
    static func describe(_ code: Int) -> (symbol: String, text: String) {
        switch code {
        case 0: return ("sun.max.fill", "晴")
        case 1: return ("sun.max.fill", "晴间多云")
        case 2: return ("cloud.sun.fill", "多云")
        case 3: return ("cloud.fill", "阴")
        case 45, 48: return ("cloud.fog.fill", "雾")
        case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", "毛毛雨")
        case 61, 63, 65, 66, 67: return ("cloud.rain.fill", "雨")
        case 71, 73, 75, 77: return ("cloud.snow.fill", "雪")
        case 80, 81, 82: return ("cloud.heavyrain.fill", "阵雨")
        case 85, 86: return ("cloud.snow.fill", "阵雪")
        case 95, 96, 99: return ("cloud.bolt.rain.fill", "雷阵雨")
        default: return ("cloud.fill", "多云")
        }
    }
}

@MainActor
final class WeatherService {
    static let shared = WeatherService()

    private var lastFetch: Date?
    private var cached: WeatherNow?

    func refresh(latitude: Double, longitude: Double, city: String,
                 completion: @escaping (WeatherNow?) -> Void) {
        if let last = lastFetch, Date().timeIntervalSince(last) < 600, let c = cached {
            completion(c)
            return
        }
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        comps?.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", latitude)),
            .init(name: "longitude", value: String(format: "%.4f", longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "hourly", value: "temperature_2m,weather_code"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto")
        ]
        guard let url = comps?.url else { completion(nil); return }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data, error == nil,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                Task { @MainActor in completion(nil) }
                return
            }
            var now = WeatherNow()
            now.city = city
            if let cur = root["current"] as? [String: Any] {
                now.temp = Int((cur["temperature_2m"] as? Double ?? 0).rounded())
                now.code = cur["weather_code"] as? Int ?? 0
            }
            if let daily = root["daily"] as? [String: Any] {
                let hi = daily["temperature_2m_max"] as? [Double] ?? []
                let lo = daily["temperature_2m_min"] as? [Double] ?? []
                if let h = hi.first { now.high = Int(h.rounded()) }
                if let l = lo.first { now.low = Int(l.rounded()) }
            }
            if let hourly = root["hourly"] as? [String: Any],
               let times = hourly["time"] as? [String],
               let temps = hourly["temperature_2m"] as? [Double],
               let codes = hourly["weather_code"] as? [Int] {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd'T'HH:mm"
                let hourFmt = DateFormatter()
                hourFmt.dateFormat = "HH时"
                let nowHour = Calendar.current.component(.hour, from: Date())
                var picked: [WeatherHour] = []
                for (i, t) in times.enumerated() {
                    guard i < temps.count, i < codes.count,
                          let date = df.date(from: t) else { continue }
                    let h = Calendar.current.component(.hour, from: date)
                    guard h >= nowHour, picked.count < 6 else { continue }
                    picked.append(WeatherHour(label: hourFmt.string(from: date),
                                              temp: Int(temps[i].rounded()),
                                              code: codes[i]))
                }
                now.hours = picked
            }
            Task { @MainActor in
                self.cached = now
                self.lastFetch = Date()
                completion(now)
            }
        }.resume()
    }
}

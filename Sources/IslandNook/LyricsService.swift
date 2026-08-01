import Foundation

struct LyricLine: Identifiable, Hashable, Sendable {
    let id: Int
    let time: Double
    let text: String
}

struct LyricsResult: Sendable {
    let lines: [LyricLine]
    let isSynced: Bool
}

enum LyricsService {
    private struct Response: Decodable {
        let instrumental: Bool
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    static func fetch(title: String, artist: String, album: String, duration: Double) async -> LyricsResult? {
        guard duration > 0 else { return nil }
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("IslandNook/1.0 (https://github.com/)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let payload = try? JSONDecoder().decode(Response.self, from: data),
              !payload.instrumental else { return nil }

        if let synced = payload.syncedLyrics {
            let lines = parseSynced(synced)
            if !lines.isEmpty { return LyricsResult(lines: lines, isSynced: true) }
        }
        if let plain = payload.plainLyrics {
            let lines = parsePlain(plain, duration: duration)
            if !lines.isEmpty { return LyricsResult(lines: lines, isSynced: false) }
        }
        return nil
    }

    static func parsePlain(_ lyrics: String, duration: Double) -> [LyricLine] {
        let texts = lyrics.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !texts.isEmpty else { return [] }
        let interval = max(3, duration / Double(texts.count))
        return texts.enumerated().map { LyricLine(id: $0.offset, time: Double($0.offset) * interval, text: $0.element) }
    }

    private static func parseSynced(_ lyrics: String) -> [LyricLine] {
        var result: [LyricLine] = []
        for rawLine in lyrics.components(separatedBy: .newlines) {
            guard rawLine.first == "[", let closing = rawLine.firstIndex(of: "]") else { continue }
            let stamp = String(rawLine[rawLine.index(after: rawLine.startIndex)..<closing])
            let parts = stamp.split(separator: ":")
            guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { continue }
            let text = rawLine[rawLine.index(after: closing)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            result.append(LyricLine(id: result.count, time: minutes * 60 + seconds, text: text))
        }
        return result.sorted { $0.time < $1.time }
    }
}

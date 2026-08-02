import AppKit
import Foundation

@MainActor
enum AppleArtworkService {
    private struct Response: Decodable { let results: [Result] }
    private struct Result: Decodable {
        let artistName: String
        let collectionName: String
        let trackName: String
        let artworkUrl100: String
        let trackTimeMillis: Double?
    }

    static func fetch(title: String, artist: String, album: String, duration: Double) async -> NSImage? {
        let localeCountry = Locale.current.region?.identifier ?? "CN"
        let countries = localeCountry == "US" ? [localeCountry] : [localeCountry, "US"]
        for country in countries {
            guard !Task.isCancelled else { return nil }
            if let image = await fetch(title: title, artist: artist, album: album, duration: duration, country: country) {
                return image
            }
        }
        return nil
    }

    private static func fetch(title: String, artist: String, album: String, duration: Double, country: String) async -> NSImage? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            .init(name: "term", value: "\(title) \(artist) \(album)"),
            .init(name: "entity", value: "song"),
            .init(name: "limit", value: "25"),
            .init(name: "country", value: country)
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadRevalidatingCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let result = bestMatch(in: decoded.results, title: title, artist: artist, album: album, duration: duration),
              let artworkURL = URL(string: result.artworkUrl100.replacingOccurrences(of: "100x100bb", with: "600x600bb")) else { return nil }

        var artworkRequest = URLRequest(url: artworkURL)
        artworkRequest.timeoutInterval = 8
        artworkRequest.cachePolicy = .returnCacheDataElseLoad
        guard let (artworkData, artworkResponse) = try? await URLSession.shared.data(for: artworkRequest),
              (artworkResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: artworkData)
    }

    private static func bestMatch(in results: [Result], title: String, artist: String, album: String, duration: Double) -> Result? {
        let expectedTitle = normalized(title)
        let expectedArtist = normalized(artist)
        let expectedAlbum = normalized(album)
        let expectedBase = editionBase(expectedAlbum)
        var best: (score: Int, result: Result)?

        for result in results {
            guard normalized(result.trackName) == expectedTitle,
                  normalized(result.artistName) == expectedArtist else { continue }
            var score = 200
            let resultAlbum = normalized(result.collectionName)
            if resultAlbum == expectedAlbum { score += 80 }
            else if editionBase(resultAlbum) == expectedBase { score += 45 }
            if duration > 0, let milliseconds = result.trackTimeMillis {
                let difference = abs(milliseconds / 1_000 - duration)
                if difference <= 1.5 { score += 60 }
                else if difference <= 4 { score += 35 }
                else if difference <= 10 { score += 10 }
                else { score -= 30 }
            }
            if best == nil || score > best!.score { best = (score, result) }
        }
        return best?.result
    }

    private static func normalized(_ value: String) -> String {
        let simplified = value.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? value
        return simplified
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "　", with: " ")
    }

    private static func editionBase(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s*-\s*(single|ep)$"#, with: "", options: [.regularExpression, .caseInsensitive])
    }
}

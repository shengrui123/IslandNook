import SwiftUI
import AppKit

@MainActor @Observable
final class MediaController {
    enum Player: String { case music = "Music", spotify = "Spotify" }
    var title = "未在播放"
    var artist = "打开 Music 或 Spotify"
    var album = ""
    var artwork: NSImage?
    var artworkColors: [Color] = ArtworkPalette.fallback
    var playerIcon: NSImage?
    var lyrics: [LyricLine] = []
    var lyricsStatus = "播放音乐后显示歌词"
    var lyricsAreSynced = false
    var playbackPosition: Double = 0
    var trackDuration: Double = 0
    private var positionUpdatedAt = Date()
    var isPlaying = false {
        didSet {
            if isPlaying != oldValue {
                if isPlaying { rhythmMonitor.start() } else { rhythmMonitor.stop() }
                playbackChanged?()
            }
        }
    }
    var player: Player?
    @ObservationIgnored var playbackChanged: (() -> Void)?
    @ObservationIgnored let rhythmMonitor = AudioRhythmMonitor()
    private var timer: Timer?
    private var artworkKey = ""
    private var artworkLoadingKey = ""
    private var artworkTask: Task<Void, Never>?
    private var lyricsKey = ""
    private var lyricsTask: Task<Void, Never>?

    func start() {
        refresh()
        timer = .scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil; rhythmMonitor.stop(); artworkTask?.cancel(); lyricsTask?.cancel() }

    var interpolatedPlaybackPosition: Double {
        min(trackDuration, playbackPosition + (isPlaying ? Date().timeIntervalSince(positionUpdatedAt) : 0))
    }

    func togglePlayback() { run(command: "playpause") }
    func next() { run(command: "next track") }
    func previous() { run(command: "previous track") }

    private func refresh() {
        if update(player: .spotify) { return }
        if update(player: .music) { return }
        player = nil; title = "未在播放"; artist = "打开 Music 或 Spotify"; album = ""; artwork = nil; artworkColors = ArtworkPalette.fallback; playerIcon = nil; artworkKey = ""; artworkLoadingKey = ""; artworkTask?.cancel(); lyricsKey = ""; lyrics = []; lyricsStatus = "播放音乐后显示歌词"; playbackPosition = 0; trackDuration = 0; isPlaying = false
    }

    @discardableResult
    private func update(player target: Player) -> Bool {
        let bundleIdentifier = target == .music ? "com.apple.Music" : "com.spotify.client"
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return false }
        let artworkLine = target == .spotify ? "set artURL to artwork url of current track" : "set artURL to \"\""
        let script = """
        tell application \"\(target.rawValue)\"
          if player state is stopped then return \"STOPPED\"
          set t to name of current track
          set a to artist of current track
          set al to album of current track
          set pos to player position
          set dur to duration of current track
          \(artworkLine)
          return (player state as text) & \"|||\" & t & \"|||\" & a & \"|||\" & al & \"|||\" & artURL & \"|||\" & pos & \"|||\" & dur
        end tell
        """
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(nil).stringValue, result != "STOPPED" else { return false }
        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 7 else { return false }
        player = target
        playerIcon = runningApp.icon
        isPlaying = parts[0].lowercased().contains("playing")
        title = parts[1]
        artist = parts[2]
        album = parts[3]
        playbackPosition = Double(parts[5]) ?? playbackPosition
        positionUpdatedAt = Date()
        let reportedDuration = Double(parts[6]) ?? 0
        trackDuration = reportedDuration > 10_000 ? reportedDuration / 1_000 : reportedDuration
        let trackKey = "\(target.rawValue)|\(title)|\(artist)|\(album)"
        if target == .spotify {
            loadRemoteArtwork(parts[4], trackKey: trackKey)
        } else {
            loadMusicArtwork(trackKey: trackKey)
        }
        loadLyricsIfNeeded(trackKey: trackKey, player: target)
        return true
    }

    private func loadLyricsIfNeeded(trackKey: String, player target: Player) {
        let onlineEnabled = UserDefaults.standard.bool(forKey: "onlineLyricsEnabled")
        let requestKey = "\(trackKey)|online=\(onlineEnabled)"
        guard lyricsKey != requestKey else { return }
        lyricsKey = requestKey
        lyricsTask?.cancel()
        lyrics = []
        lyricsStatus = "正在匹配歌词…"
        let embedded = target == .music ? embeddedMusicLyrics() : nil
        let expectedKey = requestKey
        let requestedTitle = title
        let requestedArtist = artist
        let requestedAlbum = album
        let requestedDuration = trackDuration
        lyricsTask = Task { [weak self] in
            let online = onlineEnabled ? await LyricsService.fetch(
                title: requestedTitle, artist: requestedArtist,
                album: requestedAlbum, duration: requestedDuration
            ) : nil
            guard !Task.isCancelled, self?.lyricsKey == expectedKey else { return }
            if let online {
                self?.lyrics = online.lines
                self?.lyricsAreSynced = online.isSynced
                self?.lyricsStatus = online.isSynced ? "同步歌词" : "歌词"
            } else if let embedded, !embedded.isEmpty {
                self?.lyrics = LyricsService.parsePlain(embedded, duration: requestedDuration)
                self?.lyricsAreSynced = false
                self?.lyricsStatus = "内嵌歌词"
            } else {
                self?.lyricsStatus = onlineEnabled ? "暂未找到歌词" : "可在设置中开启在线歌词"
            }
        }
    }

    private func embeddedMusicLyrics() -> String? {
        let script = """
        tell application "Music"
          try
            return lyrics of current track
          on error
            return ""
          end try
        end tell
        """
        return NSAppleScript(source: script)?.executeAndReturnError(nil).stringValue
    }

    private func loadRemoteArtwork(_ urlString: String, trackKey: String) {
        guard artworkKey != trackKey, artworkLoadingKey != trackKey else { return }
        prepareArtworkLoad(for: trackKey)
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            artworkLoadingKey = ""
            return
        }
        artworkTask = Task { [weak self] in
            let image: NSImage?
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                image = NSImage(data: data)
            } else {
                image = nil
            }
            guard let self, self.artworkLoadingKey == trackKey else { return }
            self.artworkLoadingKey = ""
            guard let image else { return }
            self.artworkKey = trackKey
            self.setArtwork(image)
        }
    }

    private func loadMusicArtwork(trackKey: String) {
        guard artworkKey != trackKey else { return }
        if artworkLoadingKey != trackKey { prepareArtworkLoad(for: trackKey) }
        let script = """
        tell application "Music"
          try
            return data of artwork 1 of current track
          on error
            return missing value
          end try
        end tell
        """
        guard let descriptor = NSAppleScript(source: script)?.executeAndReturnError(nil),
              let image = NSImage(data: descriptor.data) else { return }
        artworkLoadingKey = ""
        artworkKey = trackKey
        setArtwork(image)
    }

    private func prepareArtworkLoad(for trackKey: String) {
        artworkTask?.cancel()
        artworkLoadingKey = trackKey
        artwork = nil
        artworkColors = ArtworkPalette.fallback
    }

    private func setArtwork(_ image: NSImage) {
        artwork = image
        artworkColors = ArtworkPalette.extract(from: image)
    }

    private func run(command: String) {
        guard let player else { return }
        NSAppleScript(source: "tell application \"\(player.rawValue)\" to \(command)")?.executeAndReturnError(nil)
        refresh()
    }
}

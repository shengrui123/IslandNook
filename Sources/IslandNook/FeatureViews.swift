import SwiftUI
import AppKit
import EventKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            MediaCard(accent: accent).frame(maxWidth: .infinity)
            VStack(spacing: 10) {
                MetricCard(icon: "calendar", value: model.events.first.map { $0.start.formatted(date: .omitted, time: .shortened) } ?? "暂无", label: model.events.first?.title ?? "未来日程", accent: .blue, emphasizeLabel: true) { model.selectedTab = .calendar }
                MetricCard(icon: "tray.full.fill", value: "\(model.shelf.count)", label: "中转文件", accent: accent) { model.selectedTab = .shelf }
            }.frame(width: 180)
        }.padding(.vertical, 8)
    }
}

private struct MediaCard: View {
    @Environment(AppModel.self) private var model
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Group {
                    if let artwork = model.media.artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(colors: [accent.opacity(0.9), .blue.opacity(0.55), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: model.media.isPlaying ? "waveform" : "music.note").font(.system(size: 34, weight: .light)).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }.frame(width: 104, height: 104).clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        if let icon = model.media.playerIcon { Image(nsImage: icon).resizable().scaledToFit().frame(width: 13, height: 13) }
                        Text(model.media.player?.rawValue.uppercased() ?? "NOW PLAYING")
                    }.font(.caption2.bold()).tracking(1).foregroundStyle(accent)
                    Text(model.media.title).font(.title3.bold()).lineLimit(2)
                    Text(model.media.artist).font(.subheadline).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
            }
            LyricsPanel(accent: accent)
                .padding(.top, 7)
            Spacer(minLength: 6)
            HStack {
                Button { model.media.previous() } label: { Image(systemName: "backward.fill") }
                Spacer()
                Button { model.media.togglePlayback() } label: {
                    Image(systemName: model.media.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 46, height: 38).background(.white, in: Capsule()).foregroundStyle(.black)
                }
                Spacer()
                Button { model.media.next() } label: { Image(systemName: "forward.fill") }
            }.buttonStyle(.plain).font(.headline).padding(.horizontal, 18)
        }
        .padding(15).background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct LyricsPanel: View {
    @Environment(AppModel.self) private var model
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let lyricSnapshot = model.media.lyrics
            if lyricSnapshot.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "quote.bubble").foregroundStyle(accent.opacity(0.75))
                    Text(model.media.lyricsStatus)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let active = activeIndex(at: model.media.interpolatedPlaybackPosition, in: lyricSnapshot)
                let visibleLines = visibleLines(around: active, in: lyricSnapshot)
                VStack(spacing: 3) {
                    ForEach(visibleLines) { line in
                        Text(line.text)
                            .font(.system(size: line.id == active ? 13 : 10.5, weight: line.id == active ? .bold : .medium, design: .rounded))
                            .foregroundStyle(line.id == active ? .white : .white.opacity(0.28))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .scaleEffect(line.id == active ? 1 : 0.96)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.78), value: active)
            }
        }
        .frame(height: 62)
        .padding(.horizontal, 10)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 13))
    }

    private func activeIndex(at position: Double, in lines: [LyricLine]) -> Int {
        lines.lastIndex(where: { $0.time <= position }) ?? 0
    }

    private func visibleLines(around active: Int, in lines: [LyricLine]) -> [LyricLine] {
        [active - 1, active, active + 1]
            .filter { lines.indices.contains($0) }
            .map { lines[$0] }
    }
}

private struct MetricCard: View {
    let icon: String
    let value: String
    let label: String
    let accent: Color
    var emphasizeLabel = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(accent).frame(width: 38, height: 38).background(accent.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: emphasizeLabel ? 11 : 17, weight: emphasizeLabel ? .semibold : .bold, design: .rounded))
                        .foregroundStyle(emphasizeLabel ? .white.opacity(0.45) : .white)
                        .lineLimit(1)
                    Text(label)
                        .font(.system(size: emphasizeLabel ? 17 : 11, weight: emphasizeLabel ? .bold : .regular, design: .rounded))
                        .foregroundStyle(emphasizeLabel ? .white : .white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
            }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}

struct CalendarView: View {
    @Environment(AppModel.self) private var model
    let accent: Color
    var body: some View {
        Group {
            if model.calendarStatus == .fullAccess {
                if model.events.isEmpty {
                    ContentUnavailableView("未来 7 天没有日程", systemImage: "calendar.badge.checkmark", description: Text("你的时间看起来很自由"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(model.events) { event in
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: event.color)).frame(width: 4, height: 38)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(event.title).font(.subheadline.bold()).lineLimit(1)
                                        Text(event.start, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.white.opacity(0.5))
                                    }
                                    Spacer()
                                }.padding(10).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus").font(.system(size: 40)).foregroundStyle(accent)
                    Text("连接系统日历").font(.headline)
                    Text("只在本机读取未来 7 天的日程").font(.caption).foregroundStyle(.white.opacity(0.5))
                    Button("允许访问") { Task { await model.requestCalendarAccess() } }.buttonStyle(.borderedProminent).tint(accent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(.vertical, 8)
    }
}

struct ShelfView: View {
    @Environment(AppModel.self) private var model
    let accent: Color
    var body: some View {
        Group {
            if model.shelf.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc.fill").font(.system(size: 42)).foregroundStyle(accent)
                    Text("把文件拖到灵动岛区域").font(.headline)
                    Text("松手即可加入文件中转站；文件不会上传").font(.caption).foregroundStyle(.white.opacity(0.5))
                    Button { model.selectFiles() } label: { Label("选择文件", systemImage: "plus") }
                        .buttonStyle(.bordered).tint(accent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(model.shelf) { item in ShelfTile(item: item, accent: accent) }
                    }.padding(.horizontal, 2)
                }.scrollIndicators(.hidden)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !model.shelf.isEmpty {
                Button { model.selectFiles() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).foregroundStyle(accent).padding(10)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ShelfTile: View {
    @Environment(AppModel.self) private var model
    let item: ShelfItem; let accent: Color
    var body: some View {
        VStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().scaledToFit().frame(width: 62, height: 62)
            Text(item.name).font(.caption.bold()).lineLimit(2).multilineTextAlignment(.center).frame(width: 104)
            HStack(spacing: 12) {
                Button { model.open(item) } label: { Image(systemName: "arrow.up.forward.app") }
                Button { model.reveal(item) } label: { Image(systemName: "folder") }
                Button { model.airDrop(item) } label: { Image(systemName: "paperplane") }
                Button { model.removeShelfItem(item) } label: { Image(systemName: "xmark") }
            }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.65))
        }.padding(13).frame(width: 130, height: 172).background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct LauncherView: View {
    @Environment(AppModel.self) private var model
    let accent: Color
    var body: some View {
        VStack(spacing: 10) {
            if model.quickApps.isEmpty {
                ContentUnavailableView("添加常用应用", systemImage: "square.grid.2x2", description: Text("从刘海快速启动你的工作流"))
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(model.quickApps) { app in
                            Button { model.launch(app) } label: {
                                VStack(spacing: 8) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().scaledToFit().frame(width: 54, height: 54)
                                    Text(app.name).font(.caption.bold()).lineLimit(1)
                                }.frame(width: 98, height: 112).background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain).contextMenu { Button("移除", role: .destructive) { model.removeApp(app) } }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            Button { model.addApplications() } label: { Label("添加应用", systemImage: "plus") }.buttonStyle(.bordered).tint(accent)
        }.padding(.vertical, 8)
    }
}

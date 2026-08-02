import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("accentName") private var accentName = "紫罗兰"

    private var accent: Color {
        switch accentName {
        case "海蓝": .cyan
        case "薄荷": .mint
        case "日落": .orange
        default: .purple
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.all)
    }

    private var island: some View {
        VStack(spacing: 0) {
            if model.isExpanded {
                ExpandedNook(accent: accent)
                    .transition(.asymmetric(insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity), removal: .opacity))
            } else {
                CompactNook(accent: accent)
            }
        }
        .frame(
            width: model.isExpanded ? 590 : model.compactWidth,
            height: model.isExpanded ? 390 : model.compactHeight,
            alignment: .top
        )
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: model.isExpanded ? 28 : 13, bottomTrailingRadius: model.isExpanded ? 28 : 13)
                .fill(.black)
        }
        .contentShape(Rectangle())
        .overlay {
            if model.isFileDropTargeted {
                UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                    .overlay(alignment: .top) {
                        Label("松手加入文件中转站", systemImage: "arrow.down.doc.fill")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(accent, in: Capsule())
                            .padding(.top, 8)
                    }
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [.fileURL],
            isTargeted: Binding(
                get: { model.isFileDropTargeted },
                set: { targeted in
                    model.isFileDropTargeted = targeted
                    if targeted {
                        model.collapseTask?.cancel()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.68, blendDuration: 0.08)) {
                            model.selectedTab = .shelf
                            model.isExpanded = true
                        }
                    }
                }
            ),
            perform: acceptDrop
        )
        .onTapGesture { if !model.isExpanded { model.toggleExpanded() } }
        .animation(.spring(response: 0.2, dampingFraction: 0.84, blendDuration: 0.03), value: model.isExpanded)
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        var didAccept = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            didAccept = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let value = item as? URL { url = value }
                else { url = nil }
                if let url { Task { @MainActor in model.addFiles([url]) } }
            }
        }
        return didAccept
    }
}

private struct CompactNook: View {
    @Environment(AppModel.self) private var model
    let accent: Color

    var body: some View {
        HStack(spacing: 9) {
            if model.media.isPlaying {
                if let artwork = model.media.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: max(model.compactHeight - 12, 22), height: max(model.compactHeight - 12, 22))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            } else {
                Circle().fill(.gray.opacity(0.6)).frame(width: 7, height: 7)
                Text("IslandNook")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            if model.media.isPlaying {
                DynamicIslandWaveform(colors: model.media.artworkColors, monitor: model.media.rhythmMonitor)
                    .frame(width: 30, height: max(model.compactHeight - 14, 18))
            } else {
                Image(systemName: "chevron.down").font(.caption2.bold()).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DynamicIslandWaveform: View {
    let colors: [Color]
    let monitor: AudioRhythmMonitor

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let rhythm = monitor.levels()
            HStack(alignment: .center, spacing: 2.2) {
                ForEach(0..<5, id: \.self) { index in
                    let primary = sin(time * (4.0 + Double(index) * 0.36) + Double(index) * 1.25)
                    let liveEnergy = rhythm.indices.contains(index) ? rhythm[index] : 0.3
                    let motion = 0.76 + 0.24 * abs(primary)
                    let level = min(1, max(0.16, liveEnergy * motion))
                    Capsule()
                        .fill(colors[index % colors.count])
                        .frame(width: 3.7, height: max(4, 22 * level))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ExpandedNook: View {
    @Environment(AppModel.self) private var model
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            header
            TabContent(accent: accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            tabBar
        }
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ISLANDNOOK").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.7).foregroundStyle(accent)
                Text(model.selectedTab.rawValue).font(.system(size: 17, weight: .bold, design: .rounded))
            }
            Spacer()
            Text(Date(), format: .dateTime.weekday(.wide).hour().minute())
                .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.55))
            Button { withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { model.isExpanded = false } } label: {
                Image(systemName: "chevron.up").frame(width: 28, height: 28).background(.white.opacity(0.08), in: Circle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.bottom, 10)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(NookTab.allCases) { tab in
                Button {
                    model.collapseTask?.cancel()
                    model.tabInteractionCount += 1
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { model.selectedTab = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .symbolEffect(.bounce, value: model.selectedTab == tab ? model.tabInteractionCount : 0)
                        Text(tab.rawValue).font(.system(size: 9, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(
                    NookTabButtonStyle(
                        accent: accent,
                        isSelected: model.selectedTab == tab,
                        isHovered: model.hoveredTab == tab
                    )
                )
                .onHover { hovering in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.78)) {
                        if hovering { model.hoveredTab = tab }
                        else if model.hoveredTab == tab { model.hoveredTab = nil }
                    }
                }
            }
        }
        .padding(5)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.035), lineWidth: 1))
    }
}

private struct NookTabButtonStyle: ButtonStyle {
    let accent: Color
    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? .white : .white.opacity(isHovered ? 0.72 : 0.42))
            .background {
                RoundedRectangle(cornerRadius: 13)
                    .fill(isSelected ? accent.opacity(configuration.isPressed ? 0.42 : 0.3) : .white.opacity(isHovered ? 0.075 : 0))
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(accent.opacity(isHovered ? 0.48 : 0.22), lineWidth: 1)
                }
            }
            .shadow(color: isSelected ? accent.opacity(0.2) : .clear, radius: isHovered ? 9 : 5, y: 2)
            .scaleEffect(configuration.isPressed ? 0.93 : (isHovered ? 1.025 : 1))
            .animation(.spring(response: 0.2, dampingFraction: 0.68), value: configuration.isPressed)
            .animation(.spring(response: 0.22, dampingFraction: 0.76), value: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 13))
    }
}

private struct TabContent: View {
    @Environment(AppModel.self) private var model
    let accent: Color
    var body: some View {
        Group {
            switch model.selectedTab {
            case .home: HomeView(accent: accent)
            case .calendar: CalendarView(accent: accent)
            case .shelf: ShelfView(accent: accent)
            case .mirror: MirrorView(accent: accent)
            case .launcher: LauncherView(accent: accent)
            }
        }.transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

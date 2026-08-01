import SwiftUI
import AppKit
import EventKit
import AVFoundation

enum NookTab: String, CaseIterable, Identifiable {
    case home = "概览"
    case calendar = "日历"
    case shelf = "文件中转站"
    case mirror = "镜子"
    case launcher = "快捷启动"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: "sparkles"
        case .calendar: "calendar"
        case .shelf: "tray.full"
        case .mirror: "camera.fill"
        case .launcher: "square.grid.2x2"
        }
    }
}

struct CalendarItem: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: NSColor
}

struct ShelfItem: Identifiable, Codable, Hashable {
    let id: UUID
    let path: String
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
}

struct QuickApp: Identifiable, Codable, Hashable {
    let id: UUID
    let path: String
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

@MainActor @Observable
final class AppModel {
    var selectedTab: NookTab = .home
    var hoveredTab: NookTab?
    var tabInteractionCount = 0
    var isExpanded = false {
        didSet {
            guard isExpanded != oldValue else { return }
            expansionChanged?(isExpanded)
        }
    }
    var events: [CalendarItem] = []
    var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    var shelf: [ShelfItem] = [] { didSet { saveShelf() } }
    var quickApps: [QuickApp] = [] { didSet { saveApps() } }
    var cameraEnabled = false
    var cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
    var loginItemError: String?
    var collapseTask: Task<Void, Never>?
    var isFileDropTargeted = false
    var compactHeight: CGFloat = 38
    var compactWidth: CGFloat = 210
    @ObservationIgnored var expansionChanged: ((Bool) -> Void)?
    @ObservationIgnored var compactPresentationChanged: (() -> Void)?
    @ObservationIgnored var modalPresentationChanged: ((Bool) -> Void)?
    let media = MediaController()
    let eventStore = EKEventStore()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        loadPersistedData()
        media.playbackChanged = { [weak self] in
            self?.compactPresentationChanged?()
        }
        media.start()
        refreshCalendarIfAuthorized()
    }

    func stopServices() { media.stop(); collapseTask?.cancel() }

    func toggleExpanded() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72, blendDuration: 0.08)) {
            isExpanded.toggle()
        }
    }

    func addFiles(_ urls: [URL]) {
        let existing = Set(shelf.map(\.path))
        let additions = urls.filter { !existing.contains($0.path) }.map { ShelfItem(id: UUID(), path: $0.path) }
        shelf.append(contentsOf: additions)
        if !additions.isEmpty { selectedTab = .shelf; isExpanded = true }
    }

    func selectFiles() {
        modalPresentationChanged?(true)
        defer { modalPresentationChanged?(false) }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "加入中转站"
        guard panel.runModal() == .OK else { return }
        addFiles(panel.urls)
    }

    func removeShelfItem(_ item: ShelfItem) { shelf.removeAll { $0.id == item.id } }
    func reveal(_ item: ShelfItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    func open(_ item: ShelfItem) { NSWorkspace.shared.open(item.url) }

    func airDrop(_ item: ShelfItem) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [item.url])
    }

    func addApplications() {
        modalPresentationChanged?(true)
        defer { modalPresentationChanged?(false) }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        let existing = Set(quickApps.map(\.path))
        quickApps.append(contentsOf: panel.urls.filter { !existing.contains($0.path) }.map { QuickApp(id: UUID(), path: $0.path) })
    }

    func launch(_ app: QuickApp) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: .init())
    }

    func removeApp(_ app: QuickApp) { quickApps.removeAll { $0.id == app.id } }

    func requestCalendarAccess() async {
        do {
            calendarStatus = EKEventStore.authorizationStatus(for: .event)
            let granted = try await eventStore.requestFullAccessToEvents()
            calendarStatus = EKEventStore.authorizationStatus(for: .event)
            if granted { refreshCalendar() }
        } catch {
            calendarStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }

    func refreshCalendarIfAuthorized() {
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        if calendarStatus == .fullAccess { refreshCalendar() }
    }

    func refreshCalendar() {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(20)
            .map { CalendarItem(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "未命名事件", start: $0.startDate, end: $0.endDate, color: NSColor(cgColor: $0.calendar.cgColor) ?? .systemBlue) }
    }

    private func loadPersistedData() {
        if let data = UserDefaults.standard.data(forKey: "shelfItems"), let value = try? decoder.decode([ShelfItem].self, from: data) {
            shelf = value.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        if let data = UserDefaults.standard.data(forKey: "quickApps"), let value = try? decoder.decode([QuickApp].self, from: data) {
            quickApps = value.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    private func saveShelf() { UserDefaults.standard.set(try? encoder.encode(shelf), forKey: "shelfItems") }
    private func saveApps() { UserDefaults.standard.set(try? encoder.encode(quickApps), forKey: "quickApps") }
}

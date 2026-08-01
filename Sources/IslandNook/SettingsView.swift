import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("nookWidth") private var nookWidth = 210.0
    @AppStorage("accentName") private var accentName = "紫罗兰"
    @AppStorage("expandOnHover") private var expandOnHover = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("onlineLyricsEnabled") private var onlineLyricsEnabled = false

    var body: some View {
        TabView {
            Form {
                Section("外观") {
                    Picker("强调色", selection: $accentName) { ForEach(["紫罗兰", "海蓝", "薄荷", "日落"], id: \.self) { Text($0) } }
                    Slider(value: $nookWidth, in: 170...280, step: 5) { Text("收起宽度") } minimumValueLabel: { Text("窄") } maximumValueLabel: { Text("宽") }
                    Toggle("鼠标悬停时自动展开", isOn: $expandOnHover)
                }
                Section("行为") {
                    Toggle("登录时启动", isOn: Binding(get: { launchAtLogin }, set: setLoginItem))
                    Text("把任意文件直接拖到灵动岛区域即可加入文件中转站；点击菜单栏图标可随时打开设置。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let loginError = model.loginItemError { Text(loginError).font(.caption).foregroundStyle(.red) }
                }
                Section("歌词") {
                    Toggle("使用 LRCLIB 在线匹配同步歌词", isOn: $onlineLyricsEnabled)
                    Text("开启后会把当前歌曲名、歌手、专辑和时长发送到 LRCLIB；不会发送音频或账户信息。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).padding().tabItem { Label("通用", systemImage: "gearshape") }

            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 92, height: 92)
                    .shadow(color: .purple.opacity(0.25), radius: 14, y: 5)
                Text("IslandNook").font(.largeTitle.bold())
                Text("Version 1.0.0").foregroundStyle(.secondary)
                Text("让 Mac 顶部的每一寸空间都真正有用。\n本应用不收集或上传任何个人数据。")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).tabItem { Label("关于", systemImage: "info.circle") }
        }
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled; model.loginItemError = nil
        } catch {
            model.loginItemError = "无法更新登录项：\(error.localizedDescription)"
            launchAtLogin = false
        }
    }
}

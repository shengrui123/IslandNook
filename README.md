# IslandNook

一个原生 SwiftUI macOS 灵动岛应用，把屏幕顶部区域变成常驻的快捷工具中心。

## 功能

- 悬停展开、点击收起的刘海面板，支持所有桌面和全屏空间
- Music / Spotify 播放信息与上一首、播放暂停、下一首控制
- 系统日历未来 7 天日程
- 文件中转站：直接拖到灵动岛加入，支持打开、Finder 定位与 AirDrop
- 摄像头镜像预览
- 常用应用快捷启动
- 强调色、收起宽度、悬停行为和登录启动设置
- 所有数据仅存储在本机

## 系统要求

- macOS 14 或更高版本
- Apple Silicon 或 Intel Mac
- 完整 Xcode，或带 macOS SDK 的 Apple Command Line Tools

## 构建

```bash
make app
open dist/IslandNook.app
```

首次使用日历、摄像头或媒体控制时，macOS 会分别请求权限。媒体控制通过 Apple Events 与 Music/Spotify 通信，因此准备上架 Mac App Store 时应重新评估沙盒权限；直接分发版本可进行 Developer ID 签名与公证。

## 项目结构

- `IslandNookApp.swift`：生命周期、菜单栏入口
- `NotchPanelController.swift`：跨空间顶部悬浮面板
- `NotchRootView.swift`：灵动岛状态和动效
- `FeatureViews.swift`：媒体、日历、文件中转站、启动器
- `CameraView.swift`：AVFoundation 镜像
- `SettingsView.swift`：持久化偏好设置

import SwiftUI
@preconcurrency import AVFoundation

struct MirrorView: View {
    @Environment(AppModel.self) private var model
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.055))
            if model.cameraEnabled && model.cameraPermission == .authorized {
                CameraPreview().clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .bottom) {
                        Button { model.cameraEnabled = false } label: { Label("关闭镜子", systemImage: "camera.fill") }
                            .buttonStyle(.borderedProminent).tint(.black.opacity(0.7)).padding(12)
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.rectangle").font(.system(size: 44)).foregroundStyle(accent)
                    Text("会前快速整理一下").font(.headline)
                    Text("画面只在本机预览，不会录制或上传").font(.caption).foregroundStyle(.white.opacity(0.5))
                    Button("打开镜子") { enableCamera() }.buttonStyle(.borderedProminent).tint(accent)
                }
            }
        }.padding(.vertical, 8)
    }

    private func enableCamera() {
        switch model.cameraPermission {
        case .authorized: model.cameraEnabled = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in model.cameraPermission = AVCaptureDevice.authorizationStatus(for: .video); model.cameraEnabled = granted }
            }
        default:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
        }
    }
}

private struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewView { CameraPreviewView() }
    func updateNSView(_ nsView: CameraPreviewView, context: Context) {}
    static func dismantleNSView(_ nsView: CameraPreviewView, coordinator: ()) { nsView.stop() }
}

private final class CameraPreviewView: NSView {
    private let session = AVCaptureSession()
    private let preview = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        preview.session = session
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
        configure()
    }

    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        preview.frame = bounds
        disableMirroring()
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.beginConfiguration(); session.sessionPreset = .medium; session.addInput(input); session.commitConfiguration()
        disableMirroring()
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    private func disableMirroring() {
        guard let connection = preview.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = false
    }

    func stop() { DispatchQueue.global(qos: .utility).async { [session] in if session.isRunning { session.stopRunning() } } }
}

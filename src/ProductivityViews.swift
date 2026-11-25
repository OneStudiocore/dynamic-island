import SwiftUI
import AVFoundation

// MARK: - 待办事项

struct TodoPanel: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    var body: some View {
        VStack(spacing: 8 * s) {
            // 新增输入
            HStack(spacing: 6 * s) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 11 * s))
                    .foregroundColor(.white.opacity(0.4))
                TextField("添加一项待办，回车确认", text: Binding(
                    get: { model.todoDraft },
                    set: { model.todoDraft = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 10.5 * s))
                .foregroundColor(.white)
                .onSubmit { model.addTodo() }
            }
            .padding(.horizontal, 9 * s)
            .padding(.vertical, 6 * s)
            .background(
                RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )

            if model.todos.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 5 * s) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18 * s))
                        .foregroundColor(.white.opacity(0.22))
                    Text("还没有待办，先加一条吧")
                        .font(.system(size: 9.5 * s))
                        .foregroundColor(.white.opacity(0.3))
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4 * s) {
                        ForEach(model.todos) { item in
                            todoRow(item)
                        }
                    }
                }
            }

            HStack(spacing: 6 * s) {
                let doneCount = model.todos.filter { $0.done }.count
                Text("共 \(model.todos.count) 项 · 完成 \(doneCount) 项")
                    .font(.system(size: 8.5 * s))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                if doneCount > 0 {
                    Button { model.clearDoneTodos() } label: {
                        Text("清除已完成")
                            .font(.system(size: 8.5 * s, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 8 * s)
                            .padding(.vertical, 4 * s)
                            .background(Capsule().fill(Tokens.S.sunken))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func todoRow(_ item: TodoItem) -> some View {
        HStack(spacing: 7 * s) {
            Button { model.toggleTodo(item) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13 * s))
                    .foregroundColor(item.done
                                     ? Color(red: 0.45, green: 0.75, blue: 1.0)
                                     : .white.opacity(0.45))
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 10.5 * s, weight: .medium))
                .foregroundColor(item.done ? .white.opacity(0.46) : .white.opacity(0.85))
                .strikethrough(item.done, color: .white.opacity(0.3))
                .lineLimit(2)

            Spacer(minLength: 0)

            Button { model.deleteTodo(item) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8 * s, weight: .semibold))
                    .foregroundColor(.white.opacity(0.36))
                    .frame(width: 18 * s, height: 18 * s)
            }
            .buttonStyle(.plain)
            .help("删除")
        }
        .padding(.horizontal, 8 * s)
        .padding(.vertical, 5 * s)
        .background(
            RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

// MARK: - 速记（自动保存的常驻草稿）

struct NotesPanel: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    var body: some View {
        VStack(spacing: 7 * s) {
            HStack(spacing: 5 * s) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 10 * s, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                Text("速记 · 自动保存")
                    .font(.system(size: 9.5 * s, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                if !model.scratchpad.isEmpty {
                    Button { model.updateScratchpad("") } label: {
                        Text("清空")
                            .font(.system(size: 8.5 * s))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            TextEditor(text: Binding(
                get: { model.scratchpad },
                set: { model.updateScratchpad($0) }
            ))
            .font(.system(size: 10.5 * s))
            .foregroundColor(.white.opacity(0.9))
            .scrollContentBackground(.hidden)
            .padding(8 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10 * s, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10 * s, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )

            Text("\(model.scratchpad.count) 字")
                .font(.system(size: 8 * s))
                .foregroundColor(.white.opacity(0.32))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - 摄像头镜子

struct CameraMirrorView: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    var body: some View {
        VStack(spacing: 8 * s) {
            HStack(spacing: 5 * s) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 10 * s, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                Text("镜子")
                    .font(.system(size: 9.5 * s, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Button { model.closeCameraMirror() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13 * s))
                        .foregroundColor(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12 * s)
            .padding(.top, 10 * s)

            ZStack {
                CameraPreview(
                    onDenied: { model.cameraDenied = true },
                    onAuthStarted: { model.cameraAuthInFlight = true },
                    onAuthFinished: { model.cameraAuthInFlight = false }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )

                if model.cameraDenied {
                    deniedOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12 * s)
            .padding(.bottom, 12 * s)
        }
        // 整块不透明黑底：岛体底部本就是渐隐透明，避免后面的窗口透进来
        .background(Color.black)
    }

    private var deniedOverlay: some View {
        VStack(spacing: 6 * s) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 20 * s))
                .foregroundColor(.white.opacity(0.5))
            Text("无法使用摄像头")
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            Text("请在系统设置里允许灵动岛访问摄像头")
                .font(.system(size: 9 * s))
                .foregroundColor(.white.opacity(0.5))
            Button { model.openCameraPrivacySettings() } label: {
                Text("打开隐私设置")
                    .font(.system(size: 9.5 * s, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12 * s)
                    .padding(.vertical, 5 * s)
                    .background(Capsule().fill(Color(red: 0.18, green: 0.4, blue: 0.7)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
    }
}

struct CameraPreview: NSViewRepresentable {
    var onDenied: () -> Void
    var onAuthStarted: () -> Void
    var onAuthFinished: () -> Void

    func makeNSView(context: Context) -> CameraPreviewView {
        let v = CameraPreviewView()
        v.onDenied = onDenied
        v.onAuthStarted = onAuthStarted
        v.onAuthFinished = onAuthFinished
        v.start()
        return v
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {}

    static func dismantleNSView(_ nsView: CameraPreviewView, coordinator: ()) {
        nsView.stop()
    }
}

final class CameraPreviewView: NSView {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var configured = false
    var onDenied: (() -> Void)?
    var onAuthStarted: (() -> Void)?
    var onAuthFinished: (() -> Void)?

    override init(frame frameRect: NSRect) {
        let p = AVCaptureVideoPreviewLayer(session: session)
        p.videoGravity = .resizeAspectFill
        p.backgroundColor = NSColor.black.cgColor
        super.init(frame: frameRect)
        layer = p
        wantsLayer = true
        previewLayer = p
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            onAuthStarted?()
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.onAuthFinished?()
                    if granted { self.configureAndRun() }
                    else { self.onDenied?() }
                }
            }
        case .denied, .restricted:
            onDenied?()
        @unknown default:
            onDenied?()
        }
    }

    private func configureAndRun() {
        guard !configured,
              let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        configured = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }
}

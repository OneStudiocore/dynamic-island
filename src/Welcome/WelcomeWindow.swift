import AppKit
import SwiftUI

/// 判断这台机器上有没有「用过的痕迹」：没有任何自己的键、也没有素材/待办存下来，才算真开箱
enum UsageStore {
    static var isFreshInstall: Bool {
        let d = UserDefaults.standard
        if d.bool(forKey: "welcome.done") { return false }
        let prefixes = ["pet.", "hardware.", "island.", "hud.", "clock.", "ai.", "shortcut."]
        let anyKey = d.dictionaryRepresentation().keys.contains { k in
            prefixes.contains { k.hasPrefix($0) }
        }
        if anyKey { return false }
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicIsland")
        if let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
           !items.isEmpty { return false }
        return true
    }
}

/// 开箱向导的状态：只有页码和两个选择，用 ObservableObject 而不是 @State
@MainActor
final class WelcomeModel: ObservableObject {
    static let shared = WelcomeModel()
    enum Stage { case hello, guide }
    let clock = HelloClock()
    @Published var stage: Stage = .hello
    @Published var page = 0
    @Published var notch = true
    @Published var finished = false
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    @ObservedObject var pet = PetStore.shared
    var onClose: () -> Void

    private let pageCount = 4

    var body: some View {
        ZStack {
            if model.stage == .hello {
                HelloWriteView(clock: model.clock, onDone: {
                    withAnimation(.easeInOut(duration: 0.45)) { model.stage = .guide }
                })
                .transition(.opacity)
            } else {
                BackdropBlur()
                card
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var card: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.115), Color(white: 0.065)],
                           startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer
            }
            .padding(.horizontal, 34)
            .padding(.top, 30)
            .padding(.bottom, 22)
        }
        .frame(width: 620, height: 430)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(Color.white.opacity(0.13), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 46, x: 0, y: 22)
    }

    @ViewBuilder
    private var content: some View {
        switch model.page {
        case 0: pageIntro
        case 1: pageLook
        case 2: pagePet
        default: pageKeys
        }
    }

    // MARK: - 第 1 页

    private var pageIntro: some View {
        VStack(alignment: .leading, spacing: 18) {
            IslandCapsule(width: 190, height: 40, glow: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 8) {
                Text("灵动岛已经在你屏幕顶上了")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                Text("它平时是一颗小小的胶囊，鼠标推到屏幕顶部就会展开。")
                    .font(.system(size: 12.5))
                    .foregroundColor(.white.opacity(0.55))
            }

            HStack(spacing: 10) {
                capability("timer", "看状态", "倒计时、音乐、天气都在这儿")
                capability("doc.on.clipboard", "顺手放东西", "文件往上一拖就暂存")
                capability("sparkles", "随手问 AI", "选中模型，直接聊")
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
    }

    private func capability(_ symbol: String, _ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            Text(note)
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 158, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Color.white.opacity(0.055)))
    }

    // MARK: - 第 2 页

    private var pageLook: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("先挑一个贴合的样子")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
            Text("有刘海的机器可以完全贴住，看起来像屏幕自己长出来的。这两种随时能在设置里换。")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                lookCard(title: "贴着刘海", note: "和硬件连成一体", selected: model.notch, notch: true) {
                    model.notch = true
                }
                lookCard(title: "悬空胶囊", note: "离屏幕顶部留一点缝", selected: !model.notch, notch: false) {
                    model.notch = false
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
    }

    private func lookCard(title: String, note: String, selected: Bool, notch: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                        .frame(height: 104)
                    VStack(spacing: 0) {
                        // 一条屏幕顶边，用来交代“贴不贴”
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 7)
                        if notch {
                            IslandCapsule(width: 118, height: 24, glow: false)
                        } else {
                            Spacer().frame(height: 13)
                            IslandCapsule(width: 118, height: 24, glow: false)
                                .shadow(color: .black.opacity(0.9), radius: 8, y: 5)
                        }
                    }
                    .frame(height: 104, alignment: .top)
                }
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white.opacity(selected ? 0.95 : 0.7))
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.42))
            }
            .padding(12)
            .frame(width: 258, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white.opacity(selected ? 0.10 : 0.045)))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(selected ? 0.35 : 0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    // MARK: - 第 3 页

    private var pagePet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("要不要挂一只小东西")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
            Text("传一张全身照，它会自己认人、切开四肢，用一根绳子吊在岛下面。鼠标划过去它就晃；点一下直接开对话。")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 200, height: 168)
                    VStack(spacing: 0) {
                        IslandCapsule(width: 92, height: 22, glow: false)
                        Rectangle()
                            .fill(Color(red: 0.48, green: 0.30, blue: 0.15))
                            .frame(width: 2, height: 28)
                        figure
                            .rotationEffect(.degrees(7), anchor: .top)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: pickPhotos) {
                        Text(pet.asset == nil ? "挑一张照片" : "换一张")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.92))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .disabled(pet.busy)
                    Text(pet.asset == nil ? "最多 5 张，同一个角色的不同角度更好。照片只留在本机。"
                                          : "已经挂上了。想换就再挑一张，或者直接下一步。")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                    ToggleRow(label: "挂在岛下面", hint: nil, isOn: pet.enabled) { pet.enabled = $0 }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 第 4 页

    private var pageKeys: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("最后，记住这一个键")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
            Text("不管你在哪个 App 里，按一下就能把岛叫出来；再按一下收回去。")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))

            HStack(spacing: 10) {
                ForEach(["⌥", "⌘", "I"], id: \.self) { k in
                    Text(k)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                Text("展开 / 收起")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.leading, 6)
            }
            .padding(.top, 8)

            Text("其他设置都在菜单栏图标和设置窗口里，随时能找到。")
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.35))
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == model.page ? 0.55 : 0.16))
                    .frame(width: 5, height: 5)
            }
            Spacer()
            ghostButton(model.page == 0 ? "跳过" : "上一页") {
                if model.page == 0 {
                    model.notch = true
                    model.page = 3
                } else {
                    model.page = max(0, model.page - 1)
                }
            }

            Button(action: advance) {
                Text(model.page == 3 ? "开始用" : "继续")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(.leading, 6)
        }
    }

    private func ghostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Text(title)
            .font(.system(size: 11.5))
            .foregroundColor(.white.opacity(0.42))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    private func advance() {
        if model.page < 3 {
            model.page += 1
        } else {
            model.finished = true
            UserDefaults.standard.set(true, forKey: "welcome.done")
            onClose()
        }
    }

    /// 桌宠示意：一个能认出是人形的小剪影，比灰色方块诚实
    private var figure: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.26))
                .frame(width: 7, height: 28)
                .rotationEffect(.degrees(-24), anchor: .top)
                .offset(x: -19, y: 26)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.26))
                .frame(width: 7, height: 28)
                .rotationEffect(.degrees(24), anchor: .top)
                .offset(x: 19, y: 26)
            VStack(spacing: 3) {
                Circle()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: 21, height: 21)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.30))
                    .frame(width: 30, height: 42)
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.24))
                        .frame(width: 8, height: 24)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.24))
                        .frame(width: 8, height: 24)
                }
            }
        }
    }

    private func pickPhotos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "建桌宠"
        panel.message = "最多 5 张，同一角色的不同角度更好"
        guard panel.runModal() == .OK else { return }
        pet.importPhotos(Array(panel.urls.prefix(5)), style: pet.style)
    }
}

/// 自绘的岛示意：黑胶囊 + 一点内侧反光，比贴图省事也不用素材
struct IslandCapsule: View {
    var width: CGFloat = 160
    var height: CGFloat = 34
    var glow: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.03), Color.black],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.9)
            )
            .overlay {
                // 洞里那点冷光，是它“活着”的唯一暗示
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.55, green: 0.70, blue: 1.0).opacity(glow ? 0.30 : 0.12),
                                                  .clear],
                                         center: .center, startRadius: 0, endRadius: height * 0.9))
                    .frame(width: height * 0.32, height: height * 0.32)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Color.white.opacity(glow ? 0.10 : 0.05))
                    .frame(height: height * 0.32)
                    .padding(.horizontal, height * 0.35)
                    .padding(.top, 1.5)
            }
            .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
    }
}

/// 全屏背后的虚化层：一片毛玻璃 + 一层压暗，让桌面退到后面去
struct BackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(white: 0, alpha: 0.36).cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(tint)
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            tint.topAnchor.constraint(equalTo: v.topAnchor),
            tint.bottomAnchor.constraint(equalTo: v.bottomAnchor)
        ])
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 首次开箱：全屏虚化 + 中央一张向导卡。App 是 LSUIElement，所以自己铺一层覆盖窗
@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private var window: NSWindow?

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let screen = NSScreen.main else { return }
        let w = NSWindow(contentRect: screen.frame,
                         styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.title = ""
        w.isOpaque = false
        w.hasShadow = false
        w.backgroundColor = .clear
        // 盖住菜单栏和 Dock，才像系统开箱那一刻；
        if CommandLine.arguments.contains("--welcome-float") {
            // 演示/录制时降到普通浮层，系统录屏才拍得到
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        } else {
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        }
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false

        let model = WelcomeModel.shared
        model.page = 0
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--welcome-page=") }),
           let n = Int(arg.dropFirst("--welcome-page=".count)) {
            model.page = min(max(n, 0), 3)
        }

        let root = ZStack {
            BackdropBlur()
            WelcomeView(model: model, onClose: { [weak w] in
                w?.close()
            })
        }

        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: screen.frame.size)
        host.autoresizingMask = [.width, .height]
        w.contentView = host
        // Esc 也能退出，别把人困在向导里
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak w] ev in
            if ev.keyCode == 53, let w = w, w.isVisible {
                w.close()
                return nil
            }
            return ev
        }
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        w.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

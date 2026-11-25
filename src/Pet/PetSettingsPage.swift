import AppKit
import SwiftUI

/// 桌宠设置页：先选"正在编辑哪个角色"，下面的素材、尺寸、手感都作用在它身上
struct PetPage: View {
    @ObservedObject var roster = PetRoster.shared

    var body: some View {
        PetBody(store: roster.editingStore, roster: roster)
            .id(roster.editing)
    }
}

private struct PetBody: View {
    @ObservedObject var store: PetStore
    @ObservedObject var roster: PetRoster
    @ObservedObject var tuning = PetTuningStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsCard(title: "角色") {
                    VStack(spacing: 6) {
                        ForEach(Array(roster.stores.enumerated()), id: \.offset) { idx, st in
                            roleRow(idx, st)
                        }
                    }

                    Button(action: { _ = roster.addRole() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text("添加另一个角色")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)

                    Text("每个角色是独立的一只：自己的素材、自己的大小、自己的绳子和位置。新角色加进来后先给它传照片，桌面上会按顺序排在岛下面。")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsCard(title: "桌面宠物") {
                    ToggleRow(label: "挂在灵动岛下面",
                              hint: "一根棕色细绳吊着，鼠标划过会晃。点不着它，不影响岛上的操作。",
                              isOn: store.enabled) { store.enabled = $0 }

                    HStack(spacing: 10) {
                        Button(action: pickPhotos) {
                            HStack(spacing: 6) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 11))
                                Text(store.asset == nil ? "上传照片" : "换照片")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                        .disabled(store.busy)

                        if store.busy {
                            ProgressView().controlSize(.small)
                        }
                        Spacer()
                        if store.photosUsed > 0 {
                            Text("已用 \(store.photosUsed) / 5 张")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }

                    if let msg = store.message {
                        Text(msg)
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsCard(title: "风格") {
                    HStack(spacing: 8) {
                        ForEach(PetStyle.allCases, id: \.self) { s in
                            styleChip(s)
                        }
                    }
                    Text(store.style == .normal
                         ? "正常风格：自动抠图、按关节切成头 / 躯干 / 四肢，摆动时每个部件单独跟手。"
                         : "像素风格：整只一个像素小人，只保证会晃。")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsCard(title: "尺寸与绳长") {
                    SliderRow(label: "宠物高度", hint: "整体缩放，不影响分层",
                              value: Double(store.petHeight), range: 80...220, format: "%.0f",
                              onChange: { store.petHeight = CGFloat($0) })
                    SliderRow(label: "绳长", hint: "绳子越长，摆得越慢",
                              value: Double(store.ropeLength), range: 40...160, format: "%.0f",
                              onChange: { store.ropeLength = CGFloat($0) })
                }

                SettingsCard(title: "手感") {
                    SliderRow(label: "敏感范围", hint: "鼠标离多近才理你，调小更矜持",
                              value: tuning.radius, range: 90...320, format: "%.0f",
                              onChange: { tuning.radius = $0 })
                    SliderRow(label: "撞击力度", hint: "被划到时甩出去多狠",
                              value: tuning.power, range: 0.3...2.2, format: "%.2f×",
                              onChange: { tuning.power = $0 })
                    SliderRow(label: "软体变形", hint: "撞击瞬间的压扁拉长，0 就是硬纸片",
                              value: tuning.softness, range: 0...1, format: "%.0f", percent: true,
                              onChange: { tuning.softness = $0 })
                    SliderRow(label: "摆动周期", hint: "一个来回多久，越长越慵懒",
                              value: tuning.period, range: 1.2...4.0, format: "%.2f s",
                              onChange: { tuning.period = $0 })
                    ToggleRow(label: "静止时轻微摇摆",
                              hint: "站着不动也有一点点呼吸般的晃动",
                              isOn: tuning.idleSway) { tuning.idleSway = $0 }
                }

                SettingsCard(title: "性格") {
                    SliderRow(label: "多久不理它就开始打瞌睡",
                              hint: "调到最左边就永远精神着",
                              value: tuning.sleepAfter, range: 0...120, format: "%.0f s",
                              onChange: { tuning.sleepAfter = $0 })
                    Text("撞得急它会吓一跳，一小会儿内撞三次会撞晕；这些都是状态机自己切的，不用设。")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsCard(title: "素材") {
                    if !store.photoURLs.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(store.photoURLs.enumerated()), id: \.offset) { idx, url in
                                photoThumb(url, index: idx)
                            }
                            Spacer()
                        }
                        Text("点一张就能拿它重新建模；多的角度会一起参与，程序挑效果最好的。")
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.42))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        Text("照片、抠图、部件图都在本机，不上传。")
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.45))
                        Spacer()
                        Button(action: { store.clear(); store.message = "已清空，可以重新上传" }) {
                            Text("清空")
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 1, green: 0.45, blue: 0.4).opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
        }
    }

    // MARK: - 角色行

    private func roleRow(_ idx: Int, _ st: PetStore) -> some View {
        let on = roster.editing == idx
        let role = PetRoster.title(of: st.roleDir)
        let state = st.asset == nil ? "还没素材" : "\(st.asset?.parts.count ?? 0) 个部件"
        return HStack(spacing: 8) {
            Image(systemName: on ? "smallcircle.filled.circle" : "circle")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(on ? 0.85 : 0.35))
            Text(role)
                .font(.system(size: 11.5, weight: on ? .semibold : .regular))
                .foregroundColor(.white.opacity(on ? 0.95 : 0.6))
            Text(state)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            if roster.stores.count > 1 {
                Button(action: { roster.removeRole(at: idx) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help("从桌面移除这个角色（素材留在本机）")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(on ? 0.09 : 0.03)))
        .contentShape(Rectangle())
        .onTapGesture { roster.select(idx) }
    }

    private func styleChip(_ s: PetStyle) -> some View {
        let on = store.style == s
        return Button(action: { store.style = s }) {
            HStack(spacing: 6) {
                Image(systemName: s == .normal ? "person.crop.rectangle" : "square.grid.2x2.fill")
                    .font(.system(size: 10.5))
                Text(s.title)
                    .font(.system(size: 11.5, weight: on ? .semibold : .regular))
            }
            .foregroundColor(.white.opacity(on ? 0.95 : 0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(on ? 0.14 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(on ? 0.18 : 0), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func photoThumb(_ url: URL, index: Int) -> some View {
        let img = NSImage(contentsOf: url)
        return Button(action: {
            guard !store.busy else { return }
            store.importPhotos([url], style: store.style, keepPhotos: true)
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                if let img {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                VStack {
                    Spacer()
                    Text("第 \(index + 1) 张")
                        .font(.system(size: 8.5))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.bottom, 2)
                }
            }
            .frame(width: 44, height: 56)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .help("用这张重新建模")
    }

    /// 文件面板非阻塞弹出，必须自己留个强引用，否则函数一返回面板就被释放（看起来像"点了没反应"）
    private static var openPanel: NSOpenPanel?

    private func pickPhotos() {
        if PetBody.openPanel != nil { return }      // 已经开着一个，别叠
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "建桌宠"
        panel.message = "最多 5 张，同一角色的不同角度更好；程序取效果最好的一张来切部件"
        PetBody.openPanel = panel

        // 这是个没有 Dock 图标的辅助型 App：阻塞式 runModal 在后台窗口上经常不显示，
        // 所以改成先激活、再用非阻塞 begin，面板才一定看得见。
        NSApp.activate(ignoringOtherApps: true)
        // 兜底：辅助型 App 偶尔还是会被系统拦在别的窗口后面，半秒后没看见就强行置顶
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard let p = PetBody.openPanel, !p.isVisible else { return }
            p.level = .floating
            p.makeKeyAndOrderFront(nil)
        }
        panel.begin { resp in
            PetBody.openPanel = nil
            MainActor.assumeIsolated {
                guard resp == .OK else { return }
                let urls = Array(panel.urls.prefix(5))
                store.importPhotos(urls, style: store.style)
            }
        }
    }

}

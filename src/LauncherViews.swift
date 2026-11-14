import SwiftUI
import AppKit

// MARK: - 应用启动台

struct LauncherPanel: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 7)

    var body: some View {
        VStack(spacing: 8 * s) {
            HStack(spacing: 6 * s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10 * s))
                    .foregroundColor(.white.opacity(0.4))
                TextField("搜索应用", text: Binding(
                    get: { model.launcherQuery },
                    set: { model.launcherQuery = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12 * s))
                .foregroundColor(.white)

                if !model.launcherQuery.isEmpty {
                    Button { model.launcherQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9.5 * s))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }

                Text("\(model.filteredApps.count)")
                    .font(.system(size: 8.5 * s, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 10 * s)
            .padding(.vertical, 7 * s)
            .background(
                RoundedRectangle(cornerRadius: 10 * s, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.6)
            )

            GeometryReader { area in
                // 视图纵向高度吸附到整数行，避免底部露出半截图标
                let rowGap = 13 * s
                let rowBody = 40 * s + 4 * s + 13 * s
                let rowCount = max(1, Int(floor((area.size.height + rowGap) / (rowBody + rowGap))))
                let snapped = CGFloat(rowCount) * rowBody + CGFloat(rowCount - 1) * rowGap

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 13 * s) {
                    ForEach(model.filteredApps) { app in
                        Button { model.launch(app) } label: {
                            VStack(spacing: 4 * s) {
                                Group {
                                    if let icon = model.appIcon(app) {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                    } else {
                                        RoundedRectangle(cornerRadius: 8 * s)
                                            .fill(Color.white.opacity(0.1))
                                            .overlay(
                                                Image(systemName: "app.dashed")
                                                    .font(.system(size: 12 * s))
                                                    .foregroundColor(.white.opacity(0.4))
                                            )
                                    }
                                }
                                .frame(width: 40 * s, height: 40 * s)

                                Text(app.name)
                                    .font(.system(size: 9.5 * s))
                                    .foregroundColor(.white.opacity(0.62))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(IslandPressStyle(scale: 0.92))
                        .help(app.name)
                    }
                }
                    .padding(.horizontal, 2 * s)
                    .padding(.bottom, 14 * s)
                }
                .frame(width: area.size.width, height: min(snapped, area.size.height))
                .clipped()
            }

            if model.filteredApps.isEmpty {
                Text("没有匹配的应用")
                    .font(.system(size: 9 * s))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - 文件暂存

struct FilesPanel: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    var body: some View {
        VStack(spacing: 8 * s) {
            dropZone

            if model.stashedFiles.isEmpty {
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4 * s) {
                        ForEach(model.stashedFiles) { file in
                            fileRow(file)
                        }
                    }
                }
            }

            HStack(spacing: 6 * s) {
                Button { model.revealStashFolder() } label: {
                    Text("打开暂存目录")
                        .font(.system(size: 8.5 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 8 * s)
                        .padding(.vertical, 4 * s)
                        .background(Capsule().fill(Color(red: 0.09, green: 0.10, blue: 0.12)))
                }
                .buttonStyle(.plain)

                Spacer()

                if !model.stashedFiles.isEmpty {
                    Button { model.clearStashed() } label: {
                        Text("清空")
                            .font(.system(size: 8.5 * s, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 8 * s)
                            .padding(.vertical, 4 * s)
                            .background(Capsule().fill(Color(red: 0.09, green: 0.10, blue: 0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 3 * s) {
            Image(systemName: model.dropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 15 * s, weight: .medium))
                .foregroundColor(.white.opacity(model.dropTargeted ? 0.95 : 0.45))
            Text(model.dropTargeted ? "松手就放进灵动岛" : "把文件拖到灵动岛上，就会放进这里")
                .font(.system(size: 9.5 * s, weight: .medium))
                .foregroundColor(.white.opacity(model.dropTargeted ? 0.9 : 0.5))
            Text("也可以点一下选文件")
                .font(.system(size: 8 * s))
                .foregroundColor(.white.opacity(0.28))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54 * s)
        .background(
            RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
                .fill(Color.white.opacity(model.dropTargeted ? 0.1 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
                .strokeBorder(Color.white.opacity(model.dropTargeted ? 0.35 : 0.08),
                              style: StrokeStyle(lineWidth: 1, dash: model.dropTargeted ? [] : [5, 4]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
        .onTapGesture { pickFiles() }
    }

    private func fileRow(_ file: StashedFile) -> some View {
        HStack(spacing: 6 * s) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable()
                .frame(width: 16 * s, height: 16 * s)

            VStack(alignment: .leading, spacing: 0) {
                Text(file.name)
                    .font(.system(size: 9.5 * s, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.url.deletingLastPathComponent().path)
                    .font(.system(size: 7.5 * s))
                    .foregroundColor(.white.opacity(0.25))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 2 * s)

            Button { NSWorkspace.shared.open(file.url) } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8.5 * s))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("打开")

            Button { model.removeStashed(file) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5 * s))
                    .foregroundColor(.white.opacity(0.32))
            }
            .buttonStyle(.plain)
            .help("移出暂存")
        }
        .padding(.horizontal, 7 * s)
        .padding(.vertical, 5 * s)
        .background(
            RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(contentsOf: file.url) ?? NSItemProvider()
        }
        .help("按住可以拖出去")
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "暂存"
        panel.message = "选择要暂存到灵动岛的文件或文件夹"
        if panel.runModal() == .OK {
            model.stash(urls: panel.urls)
        }
    }
}

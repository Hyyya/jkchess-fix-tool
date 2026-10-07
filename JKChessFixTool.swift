import SwiftUI
import AppKit

// ============================================================
//  金铲铲之战 · 独立修复工具
//  专门用于解决金铲铲(com.tencent.jkchess)在 PlayCover 下的
//  闪退 / 无麦克风 / 阵容推荐UI不适配 / 安装目录缺失 四大问题
//  支持 GitHub Releases 联网自动更新
// ============================================================

// ---------------- 联网更新 ----------------
struct ReleaseInfo {
    let version: String
    let notes: String
    let zipURL: URL
}

class Updater: NSObject, ObservableObject {
    // GitHub 仓库（owner 在创建仓库后填入）
    static let owner = "Hyyya"
    static let repo  = "jkchess-fix-tool"

    @Published var checking = false
    @Published var working = false
    @Published var release: ReleaseInfo?
    @Published var showUpdate = false
    @Published var showNoUpdate = false
    @Published var showError = false
    @Published var statusText = ""

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func check(silent: Bool) {
        guard !checking, !working else { return }
        if Updater.owner == "__OWNER__" {
            if !silent { statusText = "更新源尚未配置（GitHub 仓库 owner 为空）。"; showError = true }
            return
        }
        checking = true
        let api = "https://api.github.com/repos/\(Updater.owner)/\(Updater.repo)/releases/latest"
        var req = URLRequest(url: URL(string: api)!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                self.checking = false
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    if !silent {
                        self.statusText = "检查更新失败：无法连接 GitHub（网络问题）。\n\(err?.localizedDescription ?? "")"
                        self.showError = true
                    }
                    return
                }
                let tag = (json["tag_name"] as? String) ?? ""
                var ver = tag
                if ver.hasPrefix("v") { ver = String(ver.dropFirst()) }
                let notes = (json["body"] as? String) ?? ""
                var zipURL: URL? = nil
                if let assets = json["assets"] as? [[String: Any]] {
                    for a in assets {
                        if let name = a["name"] as? String,
                           name.lowercased().hasSuffix(".zip"),
                           let u = a["browser_download_url"] as? String {
                            zipURL = URL(string: u)
                        }
                    }
                }
                guard let zu = zipURL else {
                    if !silent { self.statusText = "最新 Release 中未找到 .zip 安装包。"; self.showError = true }
                    return
                }
                if self.isNewer(ver, than: self.currentVersion) {
                    self.release = ReleaseInfo(version: ver, notes: notes, zipURL: zu)
                    self.showUpdate = true
                } else if !silent {
                    self.showNoUpdate = true
                }
            }
        }.resume()
    }

    func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").map { Int($0) ?? 0 }
        let l = local.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(r.count, l.count)
        for i in 0..<n {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    func performUpdate() {
        guard let rel = release, !working else { return }
        working = true
        statusText = "正在下载新版本 v\(rel.version)…"
        URLSession.shared.downloadTask(with: rel.zipURL) { tmp, _, err in
            let fail: (String) -> Void = { msg in
                DispatchQueue.main.async { self.working = false; self.statusText = msg; self.showError = true }
            }
            guard let tmp = tmp, err == nil else { fail("下载失败：\(err?.localizedDescription ?? "未知错误")"); return }
            let work = URL(fileURLWithPath: "/tmp/jkchess-update")
            try? FileManager.default.removeItem(at: work)
            try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("update.zip")
            do { try FileManager.default.copyItem(at: tmp, to: zip) } catch { fail("复制下载文件失败。"); return }

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = ["-o", zip.path, "-d", work.path]
            do { try p.run() } catch { fail("解压失败：无法运行 unzip。"); return }
            p.waitUntilExit()

            guard let newApp = self.findApp(in: work) else { fail("解压后未找到新版 App。"); return }
            let target = Bundle.main.bundlePath

            let script = """
            #!/bin/bash
            TARGET="\(target)"
            NEW="\(newApp.path)"
            for i in $(seq 1 20); do
              if rm -rf "$TARGET"; then break; fi
              sleep 1
            done
            cp -R "$NEW" "$TARGET"
            open "$TARGET"
            rm -rf "/tmp/jkchess-update"
            """
            let scriptPath = "/tmp/jkchess-swap.sh"
            do { try script.write(toFile: scriptPath, atomically: true, encoding: .utf8) } catch { fail("写入更新脚本失败。"); return }
            let q = Process()
            q.executableURL = URL(fileURLWithPath: "/bin/bash")
            q.arguments = ["-c", "nohup /bin/bash \(scriptPath) >/tmp/jkchess-swap.log 2>&1 &"]
            do { try q.run() } catch { fail("启动更新脚本失败。"); return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSApp.terminate(nil)
            }
        }.resume()
    }

    func findApp(in dir: URL) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for it in items {
            if it.pathExtension == "app" { return it }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: it.path, isDirectory: &isDir), isDir.boolValue {
                if let found = findApp(in: it) { return found }
            }
        }
        return nil
    }
}

// ---------------- 修复动作 ----------------
struct RepairAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let cmds: [String]
    let symbol: String
    let primary: Bool
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = NSHostingView(rootView: ContentView())
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "金铲铲修复工具"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("JKRepairMain")
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

struct StatusRow: Identifiable {
    let id = UUID()
    let key: String
    let value: String
    let good: Bool?
}

struct ContentView: View {
    @State private var updater = Updater()

    @State private var status: [StatusRow] = [
        StatusRow(key: "安装状态", value: "读取中…", good: nil),
        StatusRow(key: "游戏版本", value: "-", good: nil),
        StatusRow(key: "分辨率", value: "-", good: nil),
        StatusRow(key: "麦克风同步", value: "-", good: nil),
        StatusRow(key: "Applications目录", value: "-", good: nil),
    ]
    @State private var log = "就绪。点击「一键全部修复」或单项按钮即可。\n启动时已自动读取当前游戏状态并检查更新。"
    @State private var running = false

    let actions: [RepairAction] = [
        RepairAction(title: "一键全部修复",
                     subtitle: "目录 + 闪退 + 阵容 + 麦克风 依次处理",
                     cmds: ["appsdir", "crash", "ui", "mic"],
                     symbol: "sparkles", primary: true),
        RepairAction(title: "开启麦克风",
                     subtitle: "重置麦克风授权并同步开关",
                     cmds: ["mic"],
                     symbol: "mic.fill", primary: false),
        RepairAction(title: "阵容适配",
                     subtitle: "应用 1080p 16:9 预设",
                     cmds: ["ui"],
                     symbol: "rectangle.3.group", primary: false),
        RepairAction(title: "闪退修复",
                     subtitle: "重建目录 + 清崩溃 + 重签名",
                     cmds: ["crash"],
                     symbol: "wrench.and.screwdriver", primary: false),
        RepairAction(title: "修复Applications目录",
                     subtitle: "重建 PlayCover 安装目录",
                     cmds: ["appsdir"],
                     symbol: "folder.badge.plus", primary: false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            statusCard
            actionButtons
            logCard
            HStack {
                Spacer()
                Text("by 风轻云淡 · 微信 aucyyy")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 420)
        .onAppear {
            refreshStatus()
            updater.check(silent: true)
        }
        // 发现新版本
        .alert("发现新版本 v\(updater.release?.version ?? "")",
               isPresented: $updater.showUpdate,
               presenting: updater.release) { rel in
            Button("立即更新") { updater.performUpdate() }
            Button("稍后", role: .cancel) {}
        } message: { rel in
            Text(rel.notes.isEmpty ? "是否立即下载并更新？" : rel.notes)
        }
        // 已是最新
        .alert("已是最新版本", isPresented: $updater.showNoUpdate) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前版本 v\(updater.currentVersion)，无需更新。")
        }
        // 错误提示
        .alert("更新提示", isPresented: $updater.showError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(updater.statusText)
        }
        // 下载/安装进度
        .alert("正在更新", isPresented: $updater.working) {
            Button("取消", role: .cancel) {}
        } message: {
            Text(updater.statusText + "\n请勿关闭程序，更新完成后将自动重启。")
        }
    }

    var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 26))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("金铲铲修复工具").font(.title3.bold())
                Text("金铲铲之战 · PlayCover 独立修复 · v\(updater.currentVersion)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(spacing: 4) {
                Button { refreshStatus() } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(running)
                Button { updater.check(silent: false) } label: {
                    if updater.checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("更新", systemImage: "arrow.up.circle")
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(running || updater.checking)
            }
        }
    }

    var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前状态").font(.caption.bold()).foregroundColor(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(status) { row in
                    GridRow {
                        Text(row.key).font(.caption).foregroundColor(.secondary)
                            .gridColumnAlignment(.leading)
                        HStack(spacing: 4) {
                            if let g = row.good {
                                Image(systemName: g ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(g ? .green : .red)
                                    .font(.system(size: 11))
                            }
                            Text(row.value).font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    var actionButtons: some View {
        VStack(spacing: 8) {
            ForEach(actions) { a in
                Button(action: { run(a) }) {
                    HStack(spacing: 10) {
                        Image(systemName: a.symbol)
                            .frame(width: 22)
                            .font(.system(size: a.primary ? 17 : 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.title).font(.system(size: a.primary ? 15 : 14, weight: .semibold))
                            Text(a.subtitle).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if running { ProgressView().controlSize(.small) }
                    }
                    .padding(.vertical, a.primary ? 9 : 6)
                    .padding(.horizontal, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(a.primary ? Color.orange.opacity(0.15) : Color.gray.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(a.primary ? Color.orange.opacity(0.5) : Color.gray.opacity(0.25), lineWidth: 1)
                )
                .disabled(running)
            }
        }
    }

    var logCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("执行日志").font(.caption.bold()).foregroundColor(.secondary)
            ScrollView {
                Text(log)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(6)
            }
            .frame(maxHeight: 150)
            .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    func refreshStatus() {
        DispatchQueue.global(qos: .userInitiated).async {
            let out = ContentView.exec(["status"])
            var new: [StatusRow] = []
            var dict: [String: String] = [:]
            for line in out.split(whereSeparator: \.isNewline) {
                let s = String(line)
                if let idx = s.firstIndex(of: ":") {
                    dict[String(s[..<idx]).trimmingCharacters(in: .whitespaces)] =
                        String(s[s.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            let inst = dict["已安装"] ?? "?"
            new.append(StatusRow(key: "安装状态", value: inst,
                                 good: inst.hasPrefix("是")))
            new.append(StatusRow(key: "游戏版本", value: dict["版本"] ?? "-", good: nil))
            let res = dict["分辨率"] ?? "-"
            new.append(StatusRow(key: "分辨率", value: res, good: res.contains("16:9")))
            let mic = dict["麦克风同步"] ?? "-"
            new.append(StatusRow(key: "麦克风同步", value: mic, good: mic.lowercased().hasPrefix("true")))
            let appdir = dict["Applications目录"] ?? "-"
            new.append(StatusRow(key: "Applications目录", value: appdir, good: appdir.contains("正常")))
            DispatchQueue.main.async {
                status = new
            }
        }
    }

    func run(_ a: RepairAction) {
        guard !running else { return }
        running = true
        log = "▶ 正在执行「\(a.title)」…"
        DispatchQueue.global(qos: .userInitiated).async {
            let out = ContentView.exec(a.cmds)
            DispatchQueue.main.async {
                log = "▼ 「\(a.title)」结果：\n" + out.trimmingCharacters(in: .whitespacesAndNewlines)
                running = false
                refreshStatus()
            }
        }
    }

    static func exec(_ cmds: [String]) -> String {
        guard let res = Bundle.main.resourceURL else { return "错误：无法定位资源。" }
        let script = res.appendingPathComponent("actions.sh").path
        var all = ""
        for c in cmds {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = ["-c", "\"\(script)\" \(c)"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do { try p.run() } catch { all += "执行失败(\(c)): \(error.localizedDescription)\n"; continue }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            all += String(data: data, encoding: .utf8) ?? ""
            if cmds.count > 1 { all += "\n────\n" }
        }
        return all
    }
}

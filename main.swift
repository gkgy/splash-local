import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: WKWebView!
    let status = NSTextField(labelWithString: "正在连接 Splash…")
    let detail = NSTextField(labelWithString: "正在检查本地服务")
    let startButton = NSButton(title: "启动服务", target: nil, action: nil)
    let stopButton = NSButton(title: "停止服务", target: nil, action: nil)
    enum ServiceState { case checking, starting, ready, generating, stopping, stopped, error }
    var serviceState = ServiceState.checking
    var statusRequest = false
    var stateRevision = 0
    var busy = false
    func showState(_ state: ServiceState, _ info: String) {
        serviceState = state
        let title: String; let color: NSColor
        switch state {
        case .checking: title = "◌ 正在检查服务"; color = .systemOrange
        case .starting: title = "◌ 启动中 · 正在加载模型"; color = .systemOrange
        case .ready: title = "● 运行中 · 可以聊天"; color = .systemGreen
        case .generating: title = "● 运行中 · 正在生成"; color = .systemBlue
        case .stopping: title = "◌ 正在停止服务"; color = .systemOrange
        case .stopped: title = "○ 已停止 · 模型未运行"; color = .secondaryLabelColor
        case .error: title = "● 服务异常 · 暂不可聊天"; color = .systemRed
        }
        status.stringValue = title; status.textColor = color; detail.stringValue = info
        startButton.isEnabled = state == .stopped || state == .error
        startButton.title = (state == .ready || state == .generating) ? "已启动" : ((state == .starting || state == .checking) ? "启动中…" : "启动服务")
        stopButton.isEnabled = state == .ready || state == .generating || state == .error
        stopButton.title = state == .stopping ? "停止中…" : "停止服务"
        window?.title = "Splash Local — " + title.replacingOccurrences(of: "● ", with: "").replacingOccurrences(of: "○ ", with: "").replacingOccurrences(of: "◌ ", with: "")
    }
    func managedPID() -> String? {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["print", "gui/\(getuid())/local.splash.qwen-uncensored"]
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); p.waitUntilExit()
        for line in text.components(separatedBy: "\n") {
            let row = line.trimmingCharacters(in: .whitespaces)
            if row.hasPrefix("pid = ") { return String(row.dropFirst(6)) }
        }
        return nil
    }
    let speedLabel = NSTextField(labelWithString: "输出速度 — tok/s   ·   输出 — tokens   ·   首字等待 —   ·   等待发送消息")
    var thinkingChoice = NSPopUpButton()
    var serverThinkingChoice = NSPopUpButton()
    let thinkingValues = ["none", "low", "medium", "xhigh"]
    var settingsWindow: NSWindow?
    var logWindow: NSWindow?
    var fields: [String: NSTextField] = [:]
    var kvChoice = NSPopUpButton()
    var logText: NSTextView?
    var key = ""
    var monitor: Timer?
    var preferences: [String: Any] = ["memoryGB": 36, "contextK": 128, "cacheGB": 8, "kvFormat": "int8", "temperature": 0.7, "topP": 0.9, "topK": 20, "maxTokens": 4096, "systemPrompt": "", "thinking": "low", "serverThinking": "none"]
    var configURL: URL { home.appendingPathComponent("Library/Application Support/Splash Local/preferences.json") }
    func readPreferences() {
        if let data = try? Data(contentsOf: configURL), let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { preferences.merge(saved) { _, new in new } }
    }
    func json(_ object: Any) -> String { String(data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)! }

    let origin = "http://127.0.0.1:8000"
    let home = FileManager.default.homeDirectoryForCurrentUser
    func applicationDidFinishLaunching(_ notification: Notification) {
        readPreferences()
        let menu = NSMenu()
        let root = NSMenuItem(); menu.addItem(root)
        let appMenu = NSMenu(); root.submenu = appMenu
        appMenu.addItem(withTitle: "重新连接", action: #selector(connect), keyEquivalent: "r").target = self
        appMenu.addItem(withTitle: "查看服务日志", action: #selector(showLog), keyEquivalent: "l").target = self
        appMenu.addItem(withTitle: "参数设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "导出聊天记录…", action: #selector(exportChats), keyEquivalent: "e").target = self
        appMenu.addItem(withTitle: "停止 Splash 服务…", action: #selector(stopService), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Splash Local", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editRoot = NSMenuItem(); editRoot.title = "编辑"; menu.addItem(editRoot)
        let edit = NSMenu(title: "编辑"); editRoot.submenu = edit
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Splash Local · Qwen Uncensored Q8"
        window.minSize = NSSize(width: 760, height: 520)
        window.setFrameAutosaveName("SplashLocalWindow")
        window.isReleasedWhenClosed = false
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.add(self, name: "splashMetrics")
        config.userContentController.add(self, name: "splashThinking")
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self; web.uiDelegate = self
        let container = NSView(); window.contentView = container
        let bar = NSView(); bar.translatesAutoresizingMaskIntoConstraints = false
        status.font = .boldSystemFont(ofSize: 21); status.textColor = .systemOrange
        status.translatesAutoresizingMaskIntoConstraints = false
        startButton.target = self; startButton.action = #selector(connect); startButton.bezelStyle = .rounded
        stopButton.target = self; stopButton.action = #selector(stopService); stopButton.bezelStyle = .rounded
        detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        detail.translatesAutoresizingMaskIntoConstraints = false
        let controls = NSStackView()
        controls.orientation = .horizontal; controls.spacing = 7; controls.translatesAutoresizingMaskIntoConstraints = false
        for (title, action) in [("参数", #selector(showSettings)), ("日志", #selector(showLog))] {
            let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; controls.addArrangedSubview(b)
        }
        controls.addArrangedSubview(stopButton); controls.addArrangedSubview(startButton)
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        speedLabel.textColor = .labelColor; speedLabel.translatesAutoresizingMaskIntoConstraints = false
        speedLabel.lineBreakMode = .byTruncatingTail
        speedLabel.toolTip = "生成中用本模型分词器估算流式速度；完成后显示 Splash 返回的实际 token 数和速度。输出包含思考 token。"
        bar.addSubview(status); bar.addSubview(detail); bar.addSubview(speedLabel); bar.addSubview(controls)
        web.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar); container.addSubview(web)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: container.topAnchor), bar.leadingAnchor.constraint(equalTo: container.leadingAnchor), bar.trailingAnchor.constraint(equalTo: container.trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 112),
            status.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16), status.topAnchor.constraint(equalTo: bar.topAnchor, constant: 15), status.trailingAnchor.constraint(lessThanOrEqualTo: controls.leadingAnchor, constant: -12),
            detail.leadingAnchor.constraint(equalTo: status.leadingAnchor), detail.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 7), detail.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            speedLabel.leadingAnchor.constraint(equalTo: status.leadingAnchor), speedLabel.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 8), speedLabel.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            controls.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12), controls.topAnchor.constraint(equalTo: bar.topAnchor, constant: 17),
            web.topAnchor.constraint(equalTo: bar.bottomAnchor), web.bottomAnchor.constraint(equalTo: container.bottomAnchor), web.leadingAnchor.constraint(equalTo: container.leadingAnchor), web.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        connect()
        monitor = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshStatus() }
    }
    @objc func showLog() {
        if logWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 900,height: 600), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
            w.title = "Splash 服务日志"; w.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: w.contentView!.bounds); scroll.autoresizingMask = [.width,.height]; scroll.hasVerticalScroller = true
            let text = NSTextView(frame: scroll.bounds); text.isEditable = false; text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.autoresizingMask = [.width]; scroll.documentView = text; w.contentView?.addSubview(scroll)
            logText = text; logWindow = w; w.center()
        }
        refreshLog(); logWindow?.makeKeyAndOrderFront(nil)
    }
    func refreshLog() {
        guard logWindow?.isVisible == true || logText?.string.isEmpty == true else { return }
        if let handle = try? FileHandle(forReadingFrom: home.appendingPathComponent(".local/share/splash-qwen/server.log")) {
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 40000 ? size - 40000 : 0)
            let data = (try? handle.readToEnd()) ?? Data()
            logText?.string = String(decoding: data, as: UTF8.self)
            logText?.scrollToEndOfDocument(nil)
        }
    }
    func refreshStatus() {
        refreshLog()
        guard !busy, !key.isEmpty, !statusRequest else { return }
        statusRequest = true
        let revision = stateRevision
        var r = URLRequest(url: URL(string: origin + "/status")!); r.timeoutInterval = 3
        r.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r) { data, response, error in
            let o = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let pid = self.managedPID()
            let http = (response as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                self.statusRequest = false
                guard !self.busy, revision == self.stateRevision else { return }
                let clock = DateFormatter(); clock.dateFormat = "HH:mm:ss"
                let stamp = " · 检查于 " + clock.string(from: Date())
                if http == 200, let o = o {
                    let metal = o["metal"] as? [String: Any] ?? [:]
                    guard o["ready"] as? Bool == true, metal["healthy"] as? Bool != false else {
                        self.showState(.error, "服务有响应，但模型尚未就绪或引擎异常 · 可查看日志" + stamp); return
                    }
                    let scheduler = o["scheduler"] as? [String: Any] ?? [:]
                    let running = (scheduler["prefilling"] as? Int ?? 0) + (scheduler["decoding"] as? Int ?? 0)
                    let queued = scheduler["queued"] as? Int ?? 0
                    let context = (o["maximum_context_tokens"] as? Int ?? 0) / 1024
                    self.showState(running > 0 ? .generating : .ready, "Qwen Uncensored Q8 · 模型已就绪 · \(context)K · PID \(pid ?? "未知") · 排队 \(queued)" + stamp)
                } else if let pid = pid {
                    self.showState(.error, "进程 PID \(pid) 仍在，但 API 未就绪 · 查看日志或停止后重启" + stamp)
                } else if let http = http {
                    self.showState(.error, "端口 8000 返回 HTTP \(http)，未确认是当前 Splash 服务" + stamp)
                } else if (error as? URLError)?.code == .cannotConnectToHost {
                    self.showState(.stopped, "未检测到服务进程 · 本地 API 未监听 · 点击右侧启动服务" + stamp)
                } else {
                    self.showState(.error, "无法确认服务状态（请求超时或连接异常），请查看日志" + stamp)
                }
            }
        }.resume()
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let url = message.frameInfo.request.url, url.host == "127.0.0.1", url.port == 8000 else { return }
        if message.name == "splashThinking", let value = message.body as? String, thinkingValues.contains(value) {
            preferences["thinking"] = value
            thinkingChoice.selectItem(at: thinkingValues.firstIndex(of: value)!)
            try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONSerialization.data(withJSONObject: preferences, options: [.prettyPrinted, .sortedKeys]).write(to: configURL, options: .atomic)
            return
        }
        guard let m = message.body as? [String: Any] else { return }
        let phase = m["phase"] as? String ?? ""
        let speed = m["speed"] as? Double ?? 0
        let count = m["tokens"] as? Int ?? 0
        let elapsed = m["elapsed"] as? Double ?? 0
        let ttft = m["ttft"] as? Double
        let actual = m["actual"] as? Bool == true
        let suffix = actual ? "实测" : "估算"
        let rate = speed > 0 ? String(format: "%.1f", speed) : "—"
        let first = ttft.map { String(format: "%.2f 秒", $0) } ?? String(format: "等待 %.1f 秒", elapsed)
        let states = ["waiting":"等待首字", "generating":"生成中", "done":"已完成", "cancelled":"已取消", "interrupted":"连接中断", "error":"请求失败"]
        let thought = (m["reasoning"] as? Int).map { " · 思考 \($0) tokens" } ?? ""
        speedLabel.stringValue = "输出 \(rate) tok/s（\(suffix)） · \(count) tokens · 首字 \(first) · \(states[phase] ?? phase)" + thought
    }
    @objc func showSettings() {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x:0,y:0,width:650,height:810), styleMask:[.titled,.closable], backing:.buffered, defer:false)
        w.title = "Splash 参数"; w.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; w.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:w.contentView!.topAnchor,constant:22),stack.leadingAnchor.constraint(equalTo:w.contentView!.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:w.contentView!.trailingAnchor,constant:-24)])
        func label(_ t: String, bold: Bool = false) { let l = NSTextField(wrappingLabelWithString:t); l.font = bold ? .boldSystemFont(ofSize:14) : .systemFont(ofSize:12); stack.addArrangedSubview(l) }
        label("当前模型：Qwen3.8-27B-Uncensored · Q8_0", bold:true)
        label("引擎：独立 Splash 1.1.0 ｜ 本地 API：127.0.0.1:8000")
        label("服务参数 · 保存后需停止并重新启动服务", bold:true)
        func field(_ name: String, _ title: String) {
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 12
            let l = NSTextField(labelWithString:title); l.widthAnchor.constraint(equalToConstant:270).isActive = true
            let f = NSTextField(string: String(describing:preferences[name] ?? "")); f.widthAnchor.constraint(equalToConstant:270).isActive = true
            f.setAccessibilityLabel(title); fields[name] = f; row.addArrangedSubview(l); row.addArrangedSubview(f); stack.addArrangedSubview(row)
        }
        field("memoryGB","GPU 内存上限 GB（30–48）")
        field("contextK","上下文 K tokens（4–256）")
        field("cacheGB","磁盘缓存上限 GB（0–64，0 关闭）")
        let kvRow = NSStackView(); kvRow.orientation = .horizontal; kvRow.spacing = 12
        let kvLabel = NSTextField(labelWithString:"KV 缓存精度（BF16 更占内存）"); kvLabel.widthAnchor.constraint(equalToConstant:270).isActive = true
        kvChoice = NSPopUpButton(); kvChoice.addItems(withTitles:["int8","bf16"]); kvChoice.selectItem(withTitle:preferences["kvFormat"] as? String ?? "int8")
        kvRow.addArrangedSubview(kvLabel); kvRow.addArrangedSubview(kvChoice); stack.addArrangedSubview(kvRow)
        label("共享服务默认思考 · 所有 Agent 未指定思考参数时使用", bold:true)
        serverThinkingChoice = NSPopUpButton()
        serverThinkingChoice.addItems(withTitles:["关闭", "低", "中", "极高"])
        serverThinkingChoice.setAccessibilityLabel("共享服务默认思考")
        serverThinkingChoice.selectItem(at:thinkingValues.firstIndex(of:preferences["serverThinking"] as? String ?? "none") ?? 0)
        stack.addArrangedSubview(serverThinkingChoice)
        label("其他 Agent 的 API：http://127.0.0.1:8000/v1\n固定关闭：qwen-uncensored-splash-no-thinking\n固定低思考：qwen-uncensored-splash-thinking\n普通入口：qwen-uncensored-splash（允许请求覆盖默认值）")
        label("生成参数 · 保存后从下一条消息生效", bold:true)
        let thinkRow = NSStackView(); thinkRow.orientation = .horizontal; thinkRow.spacing = 12
        let thinkLabel = NSTextField(labelWithString: "本 App Thinking / 思考强度"); thinkLabel.widthAnchor.constraint(equalToConstant:270).isActive = true
        thinkingChoice = NSPopUpButton(); thinkingChoice.addItems(withTitles: ["关闭（更快开始回答）", "低", "中", "极高"])
        thinkingChoice.setAccessibilityLabel("默认思考强度")
        thinkingChoice.selectItem(at: thinkingValues.firstIndex(of: preferences["thinking"] as? String ?? "low") ?? 1)
        thinkRow.addArrangedSubview(thinkLabel); thinkRow.addArrangedSubview(thinkingChoice); stack.addArrangedSubview(thinkRow)
        field("temperature","Temperature（0–2）")
        field("topP","Top P（0.01–1）")
        field("topK","Top K（1–32）")
        field("maxTokens","最大输出 tokens（1–32768）")
        field("systemPrompt","系统提示词（可留空）")
        label("共享默认保存后从下次请求生效；固定入口不受 Agent 思考参数影响。聊天栏只调整本 App。所有入口共用一份模型。")
        let save = NSButton(title:"保存参数",target:self,action:#selector(saveSettings)); save.bezelStyle = .rounded; stack.addArrangedSubview(save)
        settingsWindow = w; w.center(); w.makeKeyAndOrderFront(nil)
    }
    @objc func saveSettings() {
        let rules: [(String,Double,Double,Bool)] = [("memoryGB",30,48,true),("contextK",4,256,true),("cacheGB",0,64,true),("temperature",0,2,false),("topP",0.01,1,false),("topK",1,32,true),("maxTokens",1,32768,true)]
        var next = preferences
        for (name,lo,hi,integer) in rules {
            guard let value = Double(fields[name]?.stringValue ?? ""), value.isFinite, value >= lo, value <= hi, (!integer || value.rounded() == value) else {
                let alert = NSAlert(); alert.messageText = "参数值无效"; alert.informativeText = "请检查 \(name)，范围为 \(lo)–\(hi)。"; alert.runModal(); return
            }
            next[name] = integer ? NSNumber(value:Int(value)) : NSNumber(value:value)
        }
        next["kvFormat"] = kvChoice.titleOfSelectedItem ?? "int8"
        next["systemPrompt"] = fields["systemPrompt"]?.stringValue ?? ""
        next["serverThinking"] = thinkingValues[max(0,serverThinkingChoice.indexOfSelectedItem)]
        next["thinking"] = thinkingValues[max(0,thinkingChoice.indexOfSelectedItem)]
        let needsRestart = ["memoryGB","contextK","cacheGB","kvFormat"].contains { String(describing:preferences[$0]!) != String(describing:next[$0]!) }
        do {
            try FileManager.default.createDirectory(at:configURL.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:next,options:[.prettyPrinted,.sortedKeys]).write(to:configURL,options:.atomic)
            preferences = next
            web.evaluateJavaScript("window.splashGeneration = " + json(next) + "; localStorage.setItem('splash-thinking-effort',window.splashGeneration.thinking); document.querySelector('#effort').value=window.splashGeneration.thinking;", completionHandler:nil)
            settingsWindow?.orderOut(nil)
            let a = NSAlert(); a.messageText = "参数已保存"
            a.informativeText = needsRestart ? "生成参数将在下一条消息生效。服务参数将在下次启动生效；请先停止服务，再点击启动 / 连接。" : "生成参数将在下一条消息生效。"
            a.beginSheetModal(for:window,completionHandler:nil)
        } catch { status.stringValue = "保存失败：" + error.localizedDescription }
    }
    @objc func stopService() {
        guard !busy else { return }
        let a = NSAlert(); a.messageText = "停止共享 Splash 服务？"
        a.informativeText = "会中断当前生成、释放模型内存，并暂时断开 DeepSeek Harness 等连接到端口 8000 的客户端。聊天记录和模型文件会保留。"
        a.addButton(withTitle:"停止服务"); a.addButton(withTitle:"取消")
        a.beginSheetModal(for:window) { response in
            guard response == .alertFirstButtonReturn else { return }
            self.busy = true; self.stateRevision += 1; self.showState(.stopping, "正在退出引擎并释放模型，请稍候…")
            DispatchQueue.global().async {
                let p = Process(); p.executableURL = URL(fileURLWithPath:"/bin/launchctl")
                p.arguments = ["bootout","gui/\(getuid())/local.splash.qwen-uncensored"]
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
                var stopped = false
                do { try p.run(); p.waitUntilExit(); stopped = p.terminationStatus == 0 } catch {}
                let succeeded = stopped
                DispatchQueue.main.async { self.busy = false; self.showState(.checking, succeeded ? "停止请求已完成，正在核实进程与 API…" : "正在检查服务是否已退出…"); self.refreshStatus() }
            }
        }
    }
    @objc func exportChats() {
        web.evaluateJavaScript("localStorage.getItem('splash-chats') || '[]'") { value, error in
            guard error == nil, let text = value as? String else { return }
            let panel = NSSavePanel(); panel.nameFieldStringValue = "Splash-chats.json"
            panel.beginSheetModal(for:self.window) { response in
                if response == .OK, let url = panel.url { do { try text.write(to:url,atomically:true,encoding:.utf8) } catch { self.status.stringValue = "导出失败：" + error.localizedDescription } }
            }
        }
    }
    @objc func connect() {
        guard !busy else { return }; busy = true; stateRevision += 1
        showState(.starting, "正在连接或加载 Uncensored Q8 · 模型就绪前请等待，无需重复点击")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let keyData = try Data(contentsOf: self.home.appendingPathComponent(".omlx/settings.json"))
                let settings = try JSONSerialization.jsonObject(with: keyData) as? [String: Any]
                guard let auth = settings?["auth"] as? [String: Any], let key = auth["api_key"] as? String, !key.isEmpty else {
                    throw NSError(domain: "SplashLocal", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到现有服务的认证配置"])
                }
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                p.arguments = [self.home.appendingPathComponent(".local/share/splash-qwen/ensure-server.py").path]
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
                try p.run(); p.waitUntilExit()
                guard p.terminationStatus == 0 else {
                    throw NSError(domain: "SplashLocal", code: 2, userInfo: [NSLocalizedDescriptionKey: "服务未能就绪。可从菜单打开日志，然后重新连接。"])
                }
                var request = URLRequest(url: URL(string: self.origin + "/v1/models")!); request.timeoutInterval = 10
                request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
                URLSession.shared.dataTask(with: request) { data, response, error in
                    let obj = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                    let models = obj?["data"] as? [[String: Any]] ?? []
                    let valid = (response as? HTTPURLResponse)?.statusCode == 200 && models.contains { ($0["id"] as? String) == "qwen-uncensored-splash" }
                    DispatchQueue.main.async {
                        self.busy = false
                        if valid { self.openChat(key: key) }
                        else { self.showState(.error, "端口 8000 没有返回预期的 Qwen Splash 模型，请查看日志。") }
                    }
                }.resume()
            } catch {
                DispatchQueue.main.async { self.busy = false; self.showState(.error, "启动失败：" + error.localizedDescription) }
            }
        }
    }
    func openChat(key: String) {
        self.key = key
        let generationJSON = json(preferences)
        let encoded = String(data: try! JSONSerialization.data(withJSONObject: [key]), encoding: .utf8)!
        let script = """
        (() => {
          if (location.origin !== 'http://127.0.0.1:8000') return;
          window.splashGeneration = \(generationJSON);
          const token = \(encoded)[0], originalFetch = window.fetch.bind(window);
          window.fetch = (input, init = {}) => {
            const url = new URL(input instanceof Request ? input.url : input, location.href);
            if (url.origin === location.origin && url.pathname.startsWith('/v1/')) {
              const headers = new Headers(input instanceof Request ? input.headers : undefined);
              new Headers(init.headers).forEach((v,k) => headers.set(k,v));
              headers.set('Authorization', 'Bearer ' + token);
              if (url.pathname === '/v1/chat/completions' && typeof init.body === 'string') {
                const body = JSON.parse(init.body), g = window.splashGeneration;
                Object.assign(body, {temperature:g.temperature, top_p:g.topP, top_k:g.topK, max_tokens:g.maxTokens});
                if (g.systemPrompt) body.messages = [{role:'system',content:g.systemPrompt},...body.messages.filter(m => m.role !== 'system')];
                init = {...init, body: JSON.stringify(body)};
              }
              const requestStart = performance.now();
              return originalFetch(input, {...init, headers}).then(response => {
                if (url.pathname === '/v1/chat/completions' && response.ok && response.body) {
                  return window.splashTrack(response, originalFetch, token, window.splashGeneration.thinking, requestStart);
                }
                return response;
              });
            }
            return originalFetch(input, init);
          };
          localStorage.setItem('splash-thinking-effort',window.splashGeneration.thinking || 'low');
          document.addEventListener('DOMContentLoaded', () => {
            document.documentElement.lang = 'zh-CN';
            const credentials = document.querySelector('.credentials'); if (credentials) credentials.style.display = 'none';
            const empty = document.querySelector('#empty'); if (empty) empty.textContent = '有什么我可以帮你？';
            const newChat = document.querySelector('#new-chat');
            if (newChat) for (const n of newChat.childNodes) if (n.nodeType === 3 && n.textContent.trim()) n.textContent = ' 新建对话';
            const recent = document.querySelector('.recent-label'); if (recent) recent.textContent = '最近对话';
            const input = document.querySelector('#input'); if (input) input.placeholder = '给本地 Qwen 发消息…';
            const label = document.querySelector('.effort > span'); if (label) label.textContent = '思考';
            const choices = {xhigh:'极高',medium:'中',low:'低',none:'关闭'};
            document.querySelectorAll('#effort option').forEach(o => o.textContent = choices[o.value] || o.textContent);
            document.querySelector('#send')?.setAttribute('aria-label','发送');
            document.querySelector('#effort')?.addEventListener('change',e=>window.webkit.messageHandlers.splashThinking.postMessage(e.target.value));
          });
        })();
        """
        web.configuration.userContentController.removeAllUserScripts()
        if let path = Bundle.main.path(forResource: "telemetry", ofType: "js"), let telemetry = try? String(contentsOfFile: path, encoding: .utf8) {
            web.configuration.userContentController.addUserScript(WKUserScript(source: telemetry, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        web.configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        showState(.checking, "已连接模型，正在核实引擎就绪状态…")
        refreshStatus()
        web.load(URLRequest(url: URL(string: origin)!))
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "http" && url.host == "127.0.0.1" && url.port == 8000 { decisionHandler(.allow) }
        else {
            if navigationAction.navigationType == .linkActivated && ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { status.stringValue = "页面加载失败，请点击重新连接。" }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert(); alert.messageText = message; alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = AppDelegate(); app.delegate = delegate
app.setActivationPolicy(.regular); app.run()

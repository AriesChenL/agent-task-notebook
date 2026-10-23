import SwiftUI
import Combine
import AppKit
import TaskCore

@MainActor final class Model: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var error: String?
    let store = TaskStore()
    func refresh() { do { tasks = try store.list() } catch { self.error = error.localizedDescription } }
    func save(_ draft: TaskItem, isNew: Bool) -> Bool {
        do {
            if isNew { _ = try store.create(draft) }
            else { _ = try store.update(id: draft.id, expectedRevision: draft.revision) { item in
                let history = item.activities
                item = draft; item.activities = history
                item.activities.append(Activity(draft.progress == tasks.first(where: { $0.id == draft.id })?.progress ? "编辑任务 · \(draft.status.label)" : draft.progress))
            } }
            refresh(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func changeStatus(_ task: TaskItem, to status: TaskStatus) {
        do { _ = try store.update(id: task.id, expectedRevision: task.revision) { $0.status = status; $0.activities.append(Activity("状态改为\(status.label)")) }; refresh() }
        catch { self.error = error.localizedDescription }
    }
    func delete(_ task: TaskItem) { do { try store.delete(id: task.id, expectedRevision: task.revision); refresh() } catch { self.error = error.localizedDescription } }
}
// Local tool markers; do not depend on remote image loading.
struct AgentToolIcon: View {
    let tool: String
    var size: CGFloat = 18
    private var normalized: String { tool.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isClaude: Bool { normalized.contains("claude") || normalized.contains("cloade") }
    private var isCodex: Bool { normalized.contains("codex") }
    private var tint: Color { isClaude ? Color(red: 0.82, green: 0.48, blue: 0.34) : isCodex ? .primary : .secondary }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25).fill(tint.opacity(0.12))
            Image(systemName: isClaude ? "asterisk" : isCodex ? "chevron.left.forwardslash.chevron.right" : "terminal")
                .font(.system(size: size * (isCodex ? 0.52 : 0.65), weight: .semibold))
                .foregroundStyle(tint)
        }.frame(width: size, height: size)
        .accessibilityLabel(tool)
        .help(tool)
    }
}
struct AgentToolLabel: View {
    let tool: String
    var body: some View {
        HStack(spacing: 5) { AgentToolIcon(tool: tool); Text(tool).lineLimit(1) }
    }
}
struct TagChips: View {
    let tags: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) { ForEach(tags, id: \.self) { chip($0) } }
            Text(tags.map { "#" + $0 }.joined(separator: "  ")).font(.caption).foregroundStyle(.purple).fixedSize(horizontal: false, vertical: true)
        }
    }
    func chip(_ tag: String) -> some View {
        Text("#" + tag).font(.caption).padding(.horizontal, 7).padding(.vertical, 3).background(.purple.opacity(0.10), in: Capsule()).foregroundStyle(.purple)
    }
}
extension TaskStatus {
    var color: Color { switch self { case .todo: .secondary; case .running: .blue; case .waiting: .orange; case .done: .green } }
}
@main struct NotebookApp: App {
    @StateObject private var model = Model()
    var body: some Scene {
        WindowGroup("Agent Notebook") { ContentView().environmentObject(model).frame(minWidth: 1000, minHeight: 680) }
        .defaultSize(width: 1260, height: 820)
        .commands { CommandGroup(replacing: .newItem) { Button("新建任务") { NotificationCenter.default.post(name: .init("newTask"), object: nil) }.keyboardShortcut("n") } }
    }
}
struct ContentView: View {
    @EnvironmentObject var model: Model
    @State private var filter: String? = "active"
    @State private var selection: String?
    @State private var search = ""
    @State private var editor: TaskItem?
    @State private var creating = false
    @State private var deleting: TaskItem?
    @State private var showHelp = false
    @State private var showTimeline = false
    @State private var filterDates = false
    @State private var dateFrom = Calendar.current.startOfDay(for: Date())
    @State private var dateThrough = Calendar.current.startOfDay(for: Date())
    @State private var filterTag = ""
    var tagOptions: [String] { Array(Set(model.tasks.flatMap(\.tags))).sorted() }
    var invalidDateRange: Bool { Calendar.current.startOfDay(for: dateFrom) > Calendar.current.startOfDay(for: dateThrough) }
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    var visible: [TaskItem] {
        model.tasks.filter { task in
            let matches = filter == "all" || filter == nil || (filter == "active" && task.status != .done) || task.status.rawValue == filter || (filter?.hasPrefix("tag:") == true && task.tags.contains(String(filter!.dropFirst(4))))
            let text = ([task.title, task.goal, task.directory, task.progress, task.nextStep, task.branch] + task.tags + task.sessions.flatMap { [$0.name, $0.tool, $0.sessionID] }).joined(separator: " ")
            let matchesTag = filterTag.isEmpty || task.tags.contains(filterTag)
            let from = Calendar.current.startOfDay(for: dateFrom)
            let until = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: dateThrough))!
            let matchesDate = !filterDates || (!invalidDateRange && task.overlaps(from: from, until: until))
            return matches && matchesTag && matchesDate && (search.isEmpty || text.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) { Text("AGENT").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.secondary); Text("Notebook").font(.title2.weight(.semibold)) }
                }.padding(.horizontal, 18).padding(.top, 24)
                List(selection: $filter) {
                    Section("工作台") {
                        sidebar("当前任务", icon: "square.grid.2x2", tag: "active", count: model.tasks.filter { $0.status != .done }.count)
                        sidebar("所有任务", icon: "tray.full", tag: "all", count: model.tasks.count)
                    }
                    Section("任务状态") {
                        ForEach(TaskStatus.allCases, id: \.rawValue) { status in
                            sidebar(status.label, icon: status.icon, tag: status.rawValue, count: model.tasks.filter { $0.status == status }.count, color: status.color)
                        }
                    }
                    Section("标签") {
                        ForEach(Array(Set(model.tasks.flatMap(\.tags))).sorted(), id: \.self) { tag in
                            sidebar(tag, icon: "tag", tag: "tag:" + tag, count: model.tasks.filter { $0.tags.contains(tag) }.count, color: .purple)
                        }
                        if model.tasks.allSatisfy({ $0.tags.isEmpty }) { Text("编辑任务即可添加标签").font(.caption).foregroundStyle(.secondary) }
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 10) {
                    Label("本地保存 · CLI 实时同步", systemImage: "externaldrive").font(.caption).foregroundStyle(.secondary)
                    Button { showHelp = true } label: { Label("让 Agent 接入", systemImage: "terminal") }
                    .buttonStyle(.plain).foregroundStyle(.blue)
                }.padding(18)
            }.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                workspaceHeader
                Divider().opacity(0.6)
                if showTimeline {
                    TaskTimeline(tasks: visible) { task in selection = task.id }
                } else if visible.isEmpty {
                    ContentUnavailableView {
                        Label(model.tasks.isEmpty ? "给任务一个位置" : "没有匹配的任务", systemImage: "square.grid.2x2")
                    } description: {
                        Text(model.tasks.isEmpty ? "把工作交给 Agent，把进展留在这里。" : "调整状态、标签、时间或搜索条件。")
                    } actions: {
                        Button("新建任务", action: newTask).buttonStyle(.borderedProminent)
                        if !model.tasks.isEmpty { Button("清除全部筛选") { filter = "all"; filterTag = ""; filterDates = false; search = "" } }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 290, maximum: 460), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                            ForEach(visible) { task in
                                TaskCard(task: task, open: { selection = task.id }, edit: { creating = false; editor = task })
                            }
                        }.padding(24)
                    }
                }
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar { ToolbarItem { Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("刷新") } }
        .onAppear { model.refresh() }
        .onReceive(timer) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .init("newTask"))) { _ in newTask() }
        .overlay {
            if let task = model.tasks.first(where: { $0.id == selection }) {
                GeometryReader { geometry in
                    ModalLayer(close: { selection = nil }) {
                        VStack(spacing: 0) {
                            HStack {
                                Label("任务详情", systemImage: "square.text.square").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { selection = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭详情")
                            }.padding(.horizontal, 24).padding(.vertical, 16)
                            Divider()
                            TaskDetail(task: task, edit: { creating = false; editor = task }, remove: { deleting = task })
                        }.frame(width: min(780, geometry.size.width - 80), height: min(820, geometry.size.height - 48))
                    }
                }
            }
        }
        .overlay {
            if let draft = editor {
                TaskEditor(draft: draft, isNew: creating, dismiss: { editor = nil }) { selection = $0; filter = "all" }
                    .id(draft.id)
            }
        }
        .overlay {
            if showHelp { ModalLayer(close: { showHelp = false }) { CLIHelp { showHelp = false } } }
        }
        .overlay {
            if let task = deleting {
                ModalLayer(close: { deleting = nil }) {
                    ModalMessage(title: "删除这个任务？", message: "此操作无法撤销。") {
                        Button("取消") { deleting = nil }
                        Button("删除任务", role: .destructive) { model.delete(task); selection = nil; deleting = nil }
                    }
                }
            }
        }
        .overlay {
            if let error = model.error {
                ModalLayer(close: { model.error = nil }) {
                    ModalMessage(title: "操作未完成", message: error) { Button("好") { model.error = nil } }
                }
            }
        }
    }
    var workspaceTitle: String {
        if filter?.hasPrefix("tag:") == true { return "#" + String(filter!.dropFirst(4)) }
        return filter == "all" ? "所有任务" : TaskStatus(rawValue: filter ?? "")?.label ?? "当前任务"
    }
    var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(workspaceTitle).font(.system(size: 27, weight: .semibold))
                    Text("\(visible.count) 个任务  ·  最近更新优先").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("视图", selection: $showTimeline) {
                    Label("卡片", systemImage: "square.grid.2x2").tag(false)
                    Label("时间线", systemImage: "chart.bar.xaxis").tag(true)
                }.pickerStyle(.segmented).frame(width: 178)
                Button(action: newTask) { Label("新建任务", systemImage: "plus") }.buttonStyle(.borderedProminent).controlSize(.large).tint(.primary)
            }
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索任务、目录、会话…", text: $search).textFieldStyle(.plain)
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).help("清除搜索") }
                }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                Picker("标签", selection: $filterTag) {
                    Text("全部标签").tag("")
                    ForEach(tagOptions, id: \.self) { Text($0).tag($0) }
                    if !filterTag.isEmpty && !tagOptions.contains(filterTag) { Text(filterTag + "（已无任务）").tag(filterTag) }
                }.labelsHidden().frame(width: 150)
                Toggle(isOn: $filterDates) { Label("时间筛选", systemImage: "calendar") }.toggleStyle(.button)
                if filterDates || !filterTag.isEmpty || !search.isEmpty {
                    Button("重置") { filterDates = false; filterTag = ""; search = "" }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            if filterDates {
                HStack(spacing: 12) {
                    DatePicker("从", selection: $dateFrom, displayedComponents: .date).fixedSize()
                    DatePicker("至", selection: $dateThrough, displayedComponents: .date).fixedSize()
                    Text(invalidDateRange ? "截止日期不能早于起始日期" : "匹配重叠时段，包含截止日全天")
                        .font(.caption).foregroundStyle(invalidDateRange ? .red : .secondary)
                    Spacer(minLength: 0)
                }
            }
        }.padding(24)
    }
    func newTask() { creating = true; editor = TaskItem(title: "") }
    func sidebar(_ title: String, icon: String, tag: String, count: Int, color: Color = .primary) -> some View {
        HStack { Label(title, systemImage: icon).foregroundStyle(color); Spacer(); Text("\(count)").font(.caption).foregroundStyle(.secondary) }.tag(tag)
    }
}
struct TaskDetail: View {
    @EnvironmentObject var model: Model
    let task: TaskItem
    @State private var copiedDirectory: String?
    var edit: () -> Void
    var remove: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Label(task.status.label, systemImage: task.status.icon).font(.caption.weight(.medium)).foregroundStyle(task.status.color).padding(.horizontal, 10).padding(.vertical, 6).background(task.status.color.opacity(0.09), in: Capsule())
                    Spacer()
                    Button("编辑", action: edit)
                    Menu { ForEach(TaskStatus.allCases, id: \.rawValue) { status in Button(status.label) { model.changeStatus(task, to: status) } }; Divider(); Button("删除任务", role: .destructive, action: remove) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 10) { Text(task.title).font(.system(size: 28, weight: .bold)).textSelection(.enabled); if !task.goal.isEmpty { Text(task.goal).foregroundStyle(.secondary).textSelection(.enabled) } }
                if !task.tags.isEmpty { TagChips(tags: task.tags) }
                section("任务时间", icon: "calendar") {
                    Text("开始：" + (task.startAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "未设置"))
                    Text("结束：" + (task.endAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "未设置"))
                    if let start = task.startAt, let end = task.endAt {
                        Text("时长：" + TaskTimeline.duration(end.timeIntervalSince(start))).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !task.nextStep.isEmpty {
                    VStack(alignment: .leading, spacing: 10) { Label("下一步 / 需要我做", systemImage: "arrow.turn.down.right").font(.caption.weight(.semibold)).foregroundStyle(.orange); Text(task.nextStep).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                section("最新进展", icon: "text.alignleft") { Text(task.progress.isEmpty ? "暂无进展，可以在编辑中填写，也可以由 Agent 通过 CLI 更新。" : task.progress).foregroundStyle(task.progress.isEmpty ? .secondary : .primary).textSelection(.enabled) }
                section("工作空间", icon: "folder") {
                    VStack(alignment: .leading, spacing: 12) {
                        if task.directory.isEmpty { Text("尚未关联工作目录").foregroundStyle(.secondary) }
                        else {
                            HStack {
                                Text(task.directory).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    if NSPasteboard.general.setString(task.directory, forType: .string) { copiedDirectory = task.directory }
                                } label: {
                                    Image(systemName: copiedDirectory == task.directory ? "checkmark" : "doc.on.doc")
                                }
                                .help(copiedDirectory == task.directory ? "已复制" : "复制工作目录")
                                .accessibilityLabel(copiedDirectory == task.directory ? "已复制工作目录" : "复制工作目录")
                                .onChange(of: task.id) { _, _ in copiedDirectory = nil }
                                .onChange(of: task.directory) { _, _ in copiedDirectory = nil }
                                Button { openDirectory(task.directory) } label: { Image(systemName: "arrow.up.forward.square") }.help("在 Finder 打开")
                            }
                        }
                        if !task.branch.isEmpty { Label(task.branch, systemImage: "arrow.triangle.branch").textSelection(.enabled) }
                        if !task.pr.isEmpty { HStack { Text(task.pr).font(.caption).textSelection(.enabled); Button("打开 PR") { openLink(task.pr) } } }
                    }
                }
                section("Agent 会话 · \(task.sessions.count)", icon: "bubble.left.and.bubble.right") {
                    if task.sessions.isEmpty { Text("在编辑中关联 Claude Code、Codex 或其他工具的会话。").foregroundStyle(.secondary) }
                    ForEach(task.sessions) { session in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { AgentToolLabel(tool: session.tool).font(.caption.weight(.semibold)); if !session.role.isEmpty { Text("/ \(session.role)").font(.caption).foregroundStyle(.secondary) }; Spacer(); if !session.link.isEmpty { Button("打开会话") { openLink(session.link) } } }
                            Text(session.name).font(.headline).textSelection(.enabled)
                            if !session.sessionID.isEmpty { Text(session.sessionID).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
                            if !session.directory.isEmpty { Button { openDirectory(session.directory) } label: { Label(session.directory, systemImage: "folder").font(.caption) }.buttonStyle(.plain).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                section("活动记录", icon: "clock") {
                    ForEach(task.activities.reversed().prefix(30)) { activity in
                        HStack(alignment: .top, spacing: 12) { Circle().fill(.secondary.opacity(0.4)).frame(width: 5, height: 5).padding(.top, 6); VStack(alignment: .leading, spacing: 4) { Text(activity.text).font(.callout).textSelection(.enabled); Text(activity.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary) } }.padding(.vertical, 4)
                    }
                }
                HStack { Text("ID \(task.id)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary); Spacer(); Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(task.id, forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("复制任务 ID") }
            }.padding(30).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) { Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary); content() }.frame(maxWidth: .infinity, alignment: .leading)
    }
    func openDirectory(_ path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue else { model.error = "工作目录不存在：\(path)"; return }
        if !NSWorkspace.shared.open(URL(fileURLWithPath: expanded)) { model.error = "无法打开目录" }
    }
    func openLink(_ text: String) {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["https", "http", "codex", "claude"].contains(scheme) else { model.error = "链接需要使用 http、https、codex 或 claude 协议"; return }
        if !NSWorkspace.shared.open(url) { model.error = "没有应用可以打开这个链接" }
    }
}
struct ModalLayer<Content: View>: View {
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture(perform: close)
                .accessibilityLabel("关闭弹窗")
            content()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.15)))
                .shadow(radius: 24, y: 8)
        }.onExitCommand(perform: close)
    }
}
struct ModalMessage<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title3.bold())
            Text(message).foregroundStyle(.secondary).textSelection(.enabled)
            HStack { Spacer(); actions() }
        }.padding(24).frame(width: 420)
    }
}
struct TaskEditor: View {
    @EnvironmentObject var model: Model
    let dismiss: () -> Void
    let original: TaskItem
    @State var draft: TaskItem
    let isNew: Bool
    let saved: (String) -> Void
    @State private var saveError: String?
    @State private var tagInput = ""
    @State private var confirmDiscard = false
    init(draft: TaskItem, isNew: Bool, dismiss: @escaping () -> Void, saved: @escaping (String) -> Void) {
        self.original = draft; self._draft = State(initialValue: draft)
        self.isNew = isNew; self.dismiss = dismiss; self.saved = saved
    }
    func requestClose() {
        if draft != original || !tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { confirmDiscard = true }
        else { dismiss() }
    }
    func addTags() {
        draft.tags = TaskItem.normalizeTags(draft.tags + TaskItem.parseTags(tagInput))
        tagInput = ""
    }
    var body: some View {
        GeometryReader { geometry in
            ModalLayer(close: requestClose) {
                editorForm.frame(width: min(660, geometry.size.width - 48), height: min(730, geometry.size.height - 48))
            }
        }
        .overlay {
            if confirmDiscard {
                ModalLayer(close: { confirmDiscard = false }) {
                    ModalMessage(title: "放弃未保存的修改？", message: "继续编辑可以保留当前填写的内容。") {
                        Button("继续编辑") { confirmDiscard = false }
                        Button("放弃修改", role: .destructive) { dismiss() }
                    }
                }
            }
        }
        .overlay {
            if let error = saveError {
                ModalLayer(close: { saveError = nil }) {
                    ModalMessage(title: "保存失败", message: error) { Button("好") { saveError = nil } }
                }
            }
        }
    }
    var editorForm: some View {
        VStack(spacing: 0) {
            HStack { Text(isNew ? "新建任务" : "编辑任务").font(.title3.bold()); Spacer(); Button("取消") { requestClose() }; Button("保存") { addTags(); if model.save(draft, isNew: isNew) { saved(draft.id); dismiss() } else { saveError = model.error; model.error = nil } }.buttonStyle(.borderedProminent).keyboardShortcut("s").disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.padding(20)
            Divider()
            Form {
                Section("任务") {
                    TextField("名称", text: $draft.title)
                    Picker("状态", selection: $draft.status) { ForEach(TaskStatus.allCases, id: \.self) { Text($0.label).tag($0) } }
                    TextField("目标 / 备注", text: $draft.goal, axis: .vertical).lineLimit(2...5)
                    TextField("最新进展", text: $draft.progress, axis: .vertical).lineLimit(2...5)
                    TextField("下一步 / 需要我做", text: $draft.nextStep, axis: .vertical).lineLimit(2...4)
                }
                Section("任务时间") {
                    Toggle("设置开始时间", isOn: Binding(get: { draft.startAt != nil }, set: { draft.startAt = $0 ? (draft.endAt ?? Date()) : nil }))
                    if draft.startAt != nil {
                        DatePicker("开始时间", selection: Binding(get: { draft.startAt ?? Date() }, set: { draft.startAt = $0 }), displayedComponents: [.date, .hourAndMinute])
                    }
                    Toggle("设置结束时间", isOn: Binding(get: { draft.endAt != nil }, set: { draft.endAt = $0 ? max(draft.startAt ?? Date(), Date()) : nil }))
                    if draft.endAt != nil {
                        DatePicker("结束时间", selection: Binding(get: { draft.endAt ?? Date() }, set: { draft.endAt = $0 }), displayedComponents: [.date, .hourAndMinute])
                    }
                    if let start = draft.startAt, let end = draft.endAt, end < start { Text("结束时间不能早于开始时间").foregroundStyle(.red) }
                    Text("时间由你或 Agent 设置，改变任务状态不会自动改写时间。显示时区：" + TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary)
                }
                Section("自定义标签") {
                    HStack {
                        TextField("输入标签，用逗号分隔", text: $tagInput).onSubmit { addTags() }
                        Button("添加") { addTags() }.disabled(TaskItem.parseTags(tagInput).isEmpty)
                    }
                    ForEach(draft.tags, id: \.self) { tag in
                        HStack { Label(tag, systemImage: "tag").foregroundStyle(.purple); Spacer(); Button { draft.tags.removeAll { $0 == tag } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("移除标签 " + tag) }
                    }
                    let suggestions = Array(Set(model.tasks.flatMap(\.tags))).sorted().filter { candidate in !draft.tags.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame } }
                    if !suggestions.isEmpty {
                        Menu("选择已有标签") { ForEach(suggestions, id: \.self) { tag in Button(tag) { draft.tags.append(tag) } } }
                    }
                }
                Section("工作空间") {
                    HStack { TextField("工作目录", text: $draft.directory); Button("选择…") { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                        if event.window !== panel { panel.cancel(nil); return nil }
                        return event
                    }
                    defer { if let monitor { NSEvent.removeMonitor(monitor) } }
                    if panel.runModal() == .OK, let url = panel.url { draft.directory = url.path } } }
                    TextField("分支", text: $draft.branch)
                    TextField("PR 链接", text: $draft.pr)
                }
                Section("关联 Agent 会话") {
                    ForEach($draft.sessions) { $session in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { AgentToolIcon(tool: session.tool, size: 22); TextField("工具（Claude Code / Codex / 其他）", text: $session.tool); Button(role: .destructive) { draft.sessions.removeAll { $0.id == session.id } } label: { Image(systemName: "trash") } }
                            TextField("会话名称", text: $session.name)
                            TextField("职责（实现 / Review / 调查）", text: $session.role)
                            TextField("会话 ID", text: $session.sessionID)
                            TextField("会话链接（可选）", text: $session.link)
                            TextField("会话工作目录（可选）", text: $session.directory)
                        }.padding(.vertical, 8)
                    }
                    Button { draft.sessions.append(AgentSession()) } label: { Label("添加会话", systemImage: "plus") }
                }
            }.formStyle(.grouped)
        }
    }
}
struct CLIHelp: View {
    let dismiss: () -> Void
    @State private var copied = false
    private let commands = "tasknote add --title '修复登录' --status running\ntasknote list\ntasknote session add <任务ID> --tool 'Claude Code' --name '修复登录'\ntasknote update <任务ID> --status waiting --progress '修复完成' --next '请验收'\ntasknote --help"
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Label("让 Agent 接入", systemImage: "terminal").font(.title2.bold()); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("CLI 和桌面共用本地数据。Agent 更新后，界面会在约 2 秒内刷新；不需要一直开着应用。").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("命令示例").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(commands, forType: .string)
                    } label: {
                        Label(copied ? "已复制" : "一键复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .help("复制全部命令示例")
                }
                Text(commands).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            Text("CLI 位于应用包 Contents/MacOS/tasknote。开发目录中的 scripts/install-cli.sh 可安装到 ~/.local/bin；若命令找不到，将该目录加入 PATH。").font(.caption).foregroundStyle(.secondary)
            Text("这里只记录你或 Agent 提交的信息，不会自动读取其他工具的聊天记录。").font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width: 650)
    }
}

import SwiftUI
import AppKit
import TaskCore

struct TaskCard: View {
    let task: TaskItem
    let open: () -> Void
    let edit: () -> Void
    @State private var hovering = false
    @State private var copied = false
    var tools: [String] { Array(Set(task.sessions.map(\.tool))).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(task.status.label, systemImage: task.status.icon)
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(task.status.color)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(task.status.color.opacity(0.08), in: Capsule())
                        Spacer()
                        Text(task.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(.secondary)
                            .help("最后更新：" + task.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    Text(task.title).font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(2).frame(height: 44, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.status == .waiting && !task.nextStep.isEmpty ? "需要你处理" : "最新进展")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(task.status == .waiting && !task.nextStep.isEmpty ? .orange : .secondary)
                        Text(task.status == .waiting && !task.nextStep.isEmpty ? task.nextStep : (task.progress.isEmpty ? (task.goal.isEmpty ? "还没有进展记录" : task.goal) : task.progress))
                            .font(.system(size: 12)).foregroundStyle(.primary.opacity(0.85)).lineLimit(2)
                    }.frame(height: 50, alignment: .topLeading)
                    HStack(spacing: 6) {
                        if tools.isEmpty { Label("尚未关联 Agent", systemImage: "terminal").font(.caption).foregroundStyle(.tertiary) }
                        else {
                            ForEach(Array(tools.prefix(2)), id: \.self) { tool in AgentToolLabel(tool: tool).font(.system(size: 11, weight: .medium)) }
                            if tools.count > 2 { Text("+\(tools.count - 2)").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                    }.frame(height: 20)
                    HStack(spacing: 5) {
                        ForEach(Array(task.tags.prefix(2)), id: \.self) { tag in Text("#" + tag).font(.system(size: 10)).lineLimit(1).padding(.horizontal, 7).padding(.vertical, 3).background(.primary.opacity(0.045), in: Capsule()).foregroundStyle(.secondary) }
                        if task.tags.count > 2 { Text("+\(task.tags.count - 2)").font(.caption2).foregroundStyle(.secondary) }
                        Spacer(minLength: 0)
                    }.frame(height: 22)
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text(timeLabel).lineLimit(1)
                        Spacer(minLength: 0)
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).padding(20)
            }.buttonStyle(.plain).help("查看任务：" + task.title)
            Divider().opacity(0.55)
            HStack(spacing: 8) {
                if task.directory.isEmpty {
                    Label("未关联目录", systemImage: "folder").foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text((task.directory as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle).help(task.directory)
                    Button {
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(task.directory, forType: .string)
                    } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }.buttonStyle(.plain).help(copied ? "已复制" : "复制工作目录").accessibilityLabel("复制工作目录")
                }
                Spacer(minLength: 4)
                Button(action: edit) { Image(systemName: "square.and.pencil") }.buttonStyle(.plain).help("编辑任务").accessibilityLabel("编辑任务 " + task.title)
            }.font(.system(size: 11)).padding(.horizontal, 18).padding(.vertical, 13)
        }
        .notebookGlass(radius: 24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.primary.opacity(hovering ? 0.16 : 0.04), lineWidth: 1))
        .onHover { hovering = $0 }
        .onChange(of: task.directory) { _, _ in copied = false }
    }
    var timeLabel: String {
        let formatter = DateFormatter(); formatter.dateFormat = "MM/dd HH:mm"
        if let start = task.startAt, let end = task.endAt { return formatter.string(from: start) + " → " + formatter.string(from: end) }
        if let start = task.startAt { return formatter.string(from: start) + " 开始 · 结束未设置" }
        if let end = task.endAt { return "开始未设置 · " + formatter.string(from: end) + " 结束" }
        return "未设置时间"
    }
}

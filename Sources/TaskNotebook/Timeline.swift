import SwiftUI
import TaskCore

struct TaskTimeline: View {
    let tasks: [TaskItem]
    let select: (TaskItem) -> Void
    var scheduled: [TaskItem] { tasks.filter { $0.startAt != nil || $0.endAt != nil }.sorted { ($0.startAt ?? $0.endAt!) < ($1.startAt ?? $1.endAt!) } }
    var unscheduled: [TaskItem] { tasks.filter { $0.startAt == nil && $0.endAt == nil } }
    var bounds: ClosedRange<Date> {
        let points = tasks.flatMap { [$0.startAt, $0.endAt].compactMap { $0 } }
        let first = points.min() ?? Date()
        let last = points.max() ?? first
        let padding = max(last.timeIntervalSince(first) * 0.05, 1800)
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 1 { return "不足 1 分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }
        if minutes < 1440 { return "\(minutes / 60) 小时 \(minutes % 60) 分钟" }
        return "\(minutes / 1440) 天 \((minutes % 1440) / 60) 小时"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("任务时间线").font(.title2.bold())
                    Text("\(scheduled.count) 个已设置时间 · \(unscheduled.count) 个未设置").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("跟随左侧状态、标签及搜索筛选。点击任务查看详情；在编辑中设置时间。").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) { ForEach(TaskStatus.allCases, id: \.rawValue) { status in Label { Text(status.label) } icon: { Circle().fill(status.color).frame(width: 7, height: 7) }.font(.caption) } }
            if tasks.isEmpty {
                ContentUnavailableView("没有匹配的任务", systemImage: "chart.bar.xaxis", description: Text("调整筛选条件或创建任务。"))
            } else {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        let chartWidth = max(420, geometry.size.width - 240)
                        chart(chartWidth: chartWidth)
                    }
                }
            }
        }.padding(24)
    }
    func chart(chartWidth: CGFloat) -> some View {
                        VStack(alignment: .leading, spacing: 0) {
                            if !scheduled.isEmpty {
                                HStack(spacing: 16) {
                                    Text("任务 / 时长").font(.caption).foregroundStyle(.secondary).frame(width: 200, alignment: .leading)
                                    axis(width: chartWidth)
                                }.padding(.bottom, 12)
                                ForEach(scheduled) { task in
                                    HStack(spacing: 16) {
                                        Button { select(task) } label: {
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(task.title).font(.callout.weight(.medium)).lineLimit(2)
                                                Text(description(task)).font(.caption2).foregroundStyle(.secondary)
                                            }.frame(width: 200, alignment: .leading)
                                        }.buttonStyle(.plain)
                                        bar(task, width: chartWidth)
                                    }.padding(.vertical, 12)
                                    Divider()
                                }
                                Text("只有开始或结束时间时显示圆点，不推测另一端；横条表示已填写的时间跨度。时区：\(TimeZone.current.identifier)").font(.caption2).foregroundStyle(.secondary).frame(width: chartWidth + 216, alignment: .leading).padding(.vertical, 16)
                            }
                            if !unscheduled.isEmpty {
                                Text("未设置时间").font(.headline).padding(.vertical, 16)
                                ForEach(unscheduled) { task in
                                    Button { select(task) } label: {
                                        HStack { Image(systemName: task.status.icon).foregroundStyle(task.status.color); Text(task.title); Spacer(); Text("设置时间 →").foregroundStyle(.secondary) }.frame(width: chartWidth + 216, alignment: .leading).padding(.vertical, 10)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.padding(.bottom, 16)
    }
    func description(_ task: TaskItem) -> String {
        if let start = task.startAt, let end = task.endAt { return Self.duration(end.timeIntervalSince(start)) }
        return task.startAt != nil ? "仅设置开始" : "仅设置结束"
    }
    func x(_ date: Date, width: CGFloat) -> CGFloat {
        width * min(1, max(0, date.timeIntervalSince(bounds.lowerBound) / bounds.upperBound.timeIntervalSince(bounds.lowerBound)))
    }
    func axis(width: CGFloat) -> some View {
        HStack(alignment: .top) {
            ForEach(0..<3) { index in
                if index > 0 { Spacer(minLength: 8) }
                let date = bounds.lowerBound.addingTimeInterval(bounds.upperBound.timeIntervalSince(bounds.lowerBound) * Double(index) / 2)
                VStack(spacing: 3) { Text(date, format: .dateTime.month().day()); Text(date, format: .dateTime.hour().minute()) }.font(.caption2).foregroundStyle(.secondary)
            }
        }.frame(width: width)
    }
    func bar(_ task: TaskItem, width: CGFloat) -> some View {
        let start = task.startAt ?? task.endAt!
        let end = task.endAt ?? start
        let offset = x(start, width: width)
        let span = max(6, x(end, width: width) - offset)
        let tooltip = task.title + "\n开始：" + (task.startAt.map { $0.formatted() } ?? "未设置") + "\n结束：" + (task.endAt.map { $0.formatted() } ?? "未设置")
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5).fill(.primary.opacity(0.035)).frame(height: 30)
            HStack { ForEach(0..<3) { index in if index > 0 { Spacer() }; Rectangle().fill(.primary.opacity(0.12)).frame(width: 1) } }
            if task.startAt != nil && task.endAt != nil {
                RoundedRectangle(cornerRadius: 5).fill(task.status.color.opacity(0.8)).frame(width: span, height: 26).offset(x: offset)
            } else {
                Circle().fill(task.status.color).frame(width: 10, height: 10).offset(x: offset - 5)
            }
        }.frame(width: width, height: 36).contentShape(Rectangle()).onTapGesture { select(task) }.help(tooltip).accessibilityLabel(tooltip)
    }
}

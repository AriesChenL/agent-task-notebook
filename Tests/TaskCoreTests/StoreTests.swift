import XCTest
@testable import TaskCore

final class StoreTests: XCTestCase {
    func temporaryStore() -> TaskStore { TaskStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) }
    func testRoundTripAndConflict() throws {
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let original = try store.create(TaskItem(title: "测试任务"))
        let updated = try store.update(id: original.id) { $0.status = .waiting; $0.progress = "等待验收"; var session = AgentSession(); session.name = "实现"; $0.sessions.append(session) }
        XCTAssertEqual(try store.list().first, updated)
        XCTAssertThrowsError(try store.update(id: original.id, expectedRevision: original.revision) { $0.title = "过期编辑" })
        XCTAssertThrowsError(try store.delete(id: original.id, expectedRevision: original.revision))
        XCTAssertEqual(try store.list().first?.progress, "等待验收")
    }
    func testConcurrentWritersKeepAllChanges() async throws {
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        let task = try store.create(TaskItem(title: "并发"))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for n in 0..<40 { group.addTask { _ = try store.update(id: task.id) { $0.activities.append(Activity("\(n)")) } } }
            try await group.waitForAll()
        }
        XCTAssertEqual(try store.list().first?.activities.count, 41)
        XCTAssertEqual(try store.list().first?.revision, 40)
    }
    func testCorruptionIsNotOverwritten() throws {
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        _ = try store.create(TaskItem(title: "保留"))
        let invalid = Data("broken json".utf8); try invalid.write(to: store.file)
        XCTAssertThrowsError(try store.create(TaskItem(title: "不应写入")))
        XCTAssertEqual(try Data(contentsOf: store.file), invalid)
    }
    func testLegacyDataAndTagNormalization() throws {
        let original = TaskItem(title: "旧任务")
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "tags")
        let legacy = try JSONDecoder().decode(TaskItem.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy.tags, [])
        XCTAssertEqual(legacy.id, original.id)
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        var tagged = legacy; tagged.tags = TaskItem.parseTags(" 后端,紧急，后端, Backend,backend, ")
        _ = try store.create(tagged)
        XCTAssertEqual(try store.list().first?.tags, ["后端", "紧急", "Backend"])
        _ = try store.update(id: tagged.id) { $0.tags = [] }
        XCTAssertEqual(try store.list().first?.tags, [])
    }
    func testTimeValidationAndLegacyCompatibility() throws {
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        var task = TaskItem(title: "时间测试")
        task.startAt = try TaskItem.parseTimestamp("2026-10-23T09:00:00+08:00")
        task.endAt = try TaskItem.parseTimestamp("2026-10-23T10:30:00+08:00")
        _ = try store.create(task)
        XCTAssertEqual(try store.list().first?.endAt, task.endAt)
        XCTAssertEqual(task.endAt!.timeIntervalSince(task.startAt!), 5400)
        XCTAssertThrowsError(try store.update(id: task.id) { $0.endAt = task.startAt!.addingTimeInterval(-1) })
        XCTAssertEqual(try store.list().first?.revision, 0)
        XCTAssertThrowsError(try TaskItem.parseTimestamp("tomorrow"))
        XCTAssertThrowsError(try TaskItem.parseTimestamp("2026-10-23T09:00:00"))
        XCTAssertNil(try TaskItem.parseTimestamp(""))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
        object.removeValue(forKey: "startAt"); object.removeValue(forKey: "endAt")
        let legacy = try JSONDecoder().decode(TaskItem.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.startAt); XCTAssertNil(legacy.endAt)
        _ = try store.update(id: task.id) { $0.startAt = nil; $0.endAt = nil }
        XCTAssertNil(try store.list().first?.startAt)
        task.endAt = task.startAt!.addingTimeInterval(-60)
        task.id = UUID().uuidString
        XCTAssertThrowsError(try store.create(task))
    }
    func testTimeRangeFilterBoundaries() throws {
        let from = try XCTUnwrap(TaskItem.parseTimestamp("2026-10-23T00:00:00+08:00"))
        let until = try XCTUnwrap(TaskItem.parseTimestamp("2026-10-24T00:00:00+08:00"))
        var task = TaskItem(title: "筛选")
        XCTAssertFalse(task.overlaps(from: from, until: until))
        task.startAt = from.addingTimeInterval(-3600); task.endAt = until.addingTimeInterval(3600)
        XCTAssertTrue(task.overlaps(from: from, until: until))
        task.endAt = from.addingTimeInterval(-1)
        XCTAssertFalse(task.overlaps(from: from, until: until))
        task.startAt = until; task.endAt = nil
        XCTAssertFalse(task.overlaps(from: from, until: until))
        task.startAt = from
        XCTAssertTrue(task.overlaps(from: from, until: until))
        task.startAt = nil; task.endAt = until.addingTimeInterval(-1)
        XCTAssertTrue(task.overlaps(from: from, until: until))
        XCTAssertFalse(task.overlaps(from: until, until: from))
    }
    func testEmptyTitleRejected() throws {
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.directory) }
        XCTAssertThrowsError(try store.create(TaskItem(title: "  ")))
    }
}

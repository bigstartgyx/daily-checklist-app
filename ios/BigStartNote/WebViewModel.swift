import Foundation
import SwiftUI

struct PersistedSnapshot: Codable {
    var todos: [String: [TaskItem]]
    var memos: [MemoItem]
}

struct CloudResponse: Codable {
    var ok: Bool
    var todos: [String: [TaskItem]]?
    var memos: [MemoItem]?
    var message: String?
}

struct CloudSaveRequest: Codable {
    var syncCode: String
    var todos: [String: [TaskItem]]
    var memos: [MemoItem]
}

struct MemoDraft: Identifiable {
    let id = UUID()
    var existingMemoID: String?
    var taskID: String
    var dateKey: String
    var title: String
    var content: String
}

struct TaskDraft: Identifiable {
    let id = UUID()
    var dateKey: String
    var task: TaskItem
}

struct TaskMoveDraft: Identifiable {
    let id = UUID()
    var fromDateKey: String
    var task: TaskItem
}

enum LocalStore {
    private static let snapshotFileName = "bigstart-note-state.json"
    private static let selectedDateKey = "bigstart-note-selected-date"
    private static let selectedTabKey = "bigstart-note-selected-tab"

    static func loadSnapshot() -> PersistedSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL()) else { return nil }
        return try? JSONDecoder().decode(PersistedSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: PersistedSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let url = snapshotURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func loadSelectedDate() -> Date? {
        guard let value = UserDefaults.standard.string(forKey: selectedDateKey) else { return nil }
        return DateKey.date(from: value)
    }

    static func saveSelectedDate(_ date: Date) {
        UserDefaults.standard.set(DateKey.string(from: date), forKey: selectedDateKey)
    }

    static func loadSelectedTab() -> AppTab? {
        guard let raw = UserDefaults.standard.string(forKey: selectedTabKey) else { return nil }
        return AppTab(rawValue: raw)
    }

    static func saveSelectedTab(_ tab: AppTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: selectedTabKey)
    }

    private static func snapshotURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BigStartNote", isDirectory: true).appendingPathComponent(snapshotFileName)
    }
}

enum SyncService {
    static func load(baseURL: URL, syncCode: String) async throws -> PersistedSnapshot {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/data"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "syncCode", value: syncCode)]
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(CloudResponse.self, from: data)
        guard decoded.ok else {
            throw URLError(.badServerResponse)
        }
        return PersistedSnapshot(todos: decoded.todos ?? [:], memos: decoded.memos ?? [])
    }

    static func save(baseURL: URL, syncCode: String, snapshot: PersistedSnapshot) async throws {
        let url = baseURL.appendingPathComponent("api/data")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CloudSaveRequest(syncCode: syncCode, todos: snapshot.todos, memos: snapshot.memos))
        _ = try await URLSession.shared.data(for: request)
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var isSyncing = false
    @Published var syncMessage: String?
    @Published var todosByDate: [String: [TaskItem]] = [:]
    @Published var memos: [MemoItem] = []
    @Published var selectedDate: Date = DateKey.normalized(Date())
    @Published var selectedTab: AppTab = .list
    @Published var taskInput = ""
    @Published var taskTargetDate: Date?
    @Published var showingSearch = false
    @Published var searchText = ""
    @Published var memoDraft: MemoDraft?
    @Published var taskDraft: TaskDraft?
    @Published var moveDraft: TaskMoveDraft?
    @Published var highlightedTaskID: String?
    @Published var highlightedMemoID: String?
    @Published var openSwipeID: String?

    let config: AppConfig
    private var didBootstrap = false

    init(config: AppConfig = .shared) {
        self.config = config
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        if let snapshot = LocalStore.loadSnapshot() {
            apply(snapshot: snapshot)
        }
        selectedDate = LocalStore.loadSelectedDate() ?? selectedDate
        selectedTab = LocalStore.loadSelectedTab() ?? selectedTab

        do {
            let snapshot = try await SyncService.load(baseURL: config.apiBaseURL, syncCode: config.syncCode)
            apply(snapshot: snapshot)
            persistLocal()
        } catch {
            if todosByDate.isEmpty && memos.isEmpty {
                syncMessage = "云端加载失败，当前显示本地空数据。"
            }
        }

        isLoading = false
    }

    func persistPreferences() {
        LocalStore.saveSelectedDate(selectedDate)
        LocalStore.saveSelectedTab(selectedTab)
    }

    func titleForSelectedDate() -> String {
        DateKey.isToday(selectedDate) ? "今天" : DateKey.longTitle(for: selectedDate)
    }

    func inputDateLabel() -> String {
        DateKey.shortDateLabel(for: taskTargetDate ?? selectedDate)
    }

    func dateKey(for date: Date) -> String {
        DateKey.string(from: date)
    }

    func setSelectedDate(_ date: Date) {
        selectedDate = DateKey.normalized(date)
        persistPreferences()
    }

    func setSelectedTab(_ tab: AppTab) {
        selectedTab = tab
        persistPreferences()
    }

    func tasks(for date: Date) -> [TaskItem] {
        tasks(forKey: dateKey(for: date))
    }

    func tasks(forKey key: String) -> [TaskItem] {
        let list = todosByDate[key] ?? []
        return list.sorted(by: taskSort(lhs:rhs:))
    }

    func sections(for key: String) -> TaskSections {
        let list = tasks(forKey: key)
        return TaskSections(
            pinned: list.filter { $0.pinnedAt != nil },
            active: list.filter { $0.pinnedAt == nil && !$0.done },
            completed: list.filter { $0.pinnedAt == nil && $0.done }
        )
    }

    func progress(for key: String) -> (done: Int, total: Int, percent: Double) {
        let list = todosByDate[key] ?? []
        let done = list.filter(\.done).count
        return (done, list.count, list.isEmpty ? 0 : Double(done) / Double(list.count))
    }

    func addTask() {
        let trimmed = taskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let targetDate = taskTargetDate ?? selectedDate
        let key = dateKey(for: targetDate)
        var list = todosByDate[key] ?? []
        list.append(TaskItem.make(text: trimmed))
        todosByDate[key] = list
        taskInput = ""
        taskTargetDate = nil
        persistAndSync()
    }

    func updateTask(_ task: TaskItem, dateKey: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateTask(id: task.id, dateKey: dateKey) { item in
            item.text = trimmed
        }
    }

    func toggleDone(task: TaskItem, dateKey: String) {
        mutateTask(id: task.id, dateKey: dateKey) { item in
            item.done.toggle()
            item.completedAt = item.done ? Date().timeIntervalSince1970 * 1000 : nil
        }
    }

    func deleteTask(task: TaskItem, dateKey: String) {
        guard var list = todosByDate[dateKey] else { return }
        list.removeAll { $0.id == task.id }
        todosByDate[dateKey] = list
        persistAndSync()
    }

    func togglePin(task: TaskItem, dateKey: String) {
        mutateTask(id: task.id, dateKey: dateKey) { item in
            item.pinnedAt = item.pinnedAt == nil ? (Date().timeIntervalSince1970 * 1000) : nil
        }
    }

    func moveTask(task: TaskItem, from dateKey: String, to date: Date) {
        let targetKey = self.dateKey(for: date)
        guard targetKey != dateKey else { return }
        guard var fromList = todosByDate[dateKey] else { return }
        guard let index = fromList.firstIndex(where: { $0.id == task.id }) else { return }
        let moved = fromList.remove(at: index)
        todosByDate[dateKey] = fromList
        var targetList = todosByDate[targetKey] ?? []
        targetList.append(moved)
        todosByDate[targetKey] = targetList
        memos = memos.map { memo in
            var copy = memo
            if copy.taskId == task.id {
                copy.date = targetKey
            }
            return copy
        }
        persistAndSync()
    }

    func hasMemo(for task: TaskItem, dateKey: String) -> Bool {
        memos.contains { memo in
            memo.taskId == task.id || (memo.date == dateKey && memo.taskTitle == task.text)
        }
    }

    func openTaskEditor(task: TaskItem, dateKey: String) {
        taskDraft = TaskDraft(dateKey: dateKey, task: task)
    }

    func openMoveEditor(task: TaskItem, dateKey: String) {
        moveDraft = TaskMoveDraft(fromDateKey: dateKey, task: task)
    }

    func openMemoEditorForTask(task: TaskItem, dateKey: String) {
        let existing = memos.first { $0.taskId == task.id || ($0.date == dateKey && $0.taskTitle == task.text) }
        memoDraft = MemoDraft(
            existingMemoID: existing?.id,
            taskID: task.id,
            dateKey: dateKey,
            title: existing?.taskTitle ?? task.text,
            content: existing?.content ?? ""
        )
    }

    func openNewMemo() {
        let key = dateKey(for: selectedDate)
        memoDraft = MemoDraft(existingMemoID: nil, taskID: "new-\(UUID().uuidString)", dateKey: key, title: "", content: "")
    }

    func saveMemo(_ draft: MemoDraft) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "备忘" : draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = draft.existingMemoID, let index = memos.firstIndex(where: { $0.id == id }) {
            memos[index].taskTitle = title
            memos[index].content = content
        } else {
            memos.insert(MemoItem.make(taskId: draft.taskID, date: draft.dateKey, taskTitle: title, content: content), at: 0)
        }
        persistAndSync()
    }

    func deleteMemo(_ memo: MemoItem) {
        memos.removeAll { $0.id == memo.id }
        persistAndSync()
    }

    func openMemoEditor(_ memo: MemoItem) {
        memoDraft = MemoDraft(
            existingMemoID: memo.id,
            taskID: memo.taskId,
            dateKey: memo.date,
            title: memo.taskTitle,
            content: memo.content
        )
    }

    func memosSorted() -> [MemoItem] {
        memos.sorted { $0.createdAt > $1.createdAt }
    }

    func searchResults() -> [SearchResultItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        var results: [SearchResultItem] = []

        for key in todosByDate.keys.sorted(by: >) {
            for task in todosByDate[key] ?? [] where task.text.lowercased().contains(query) {
                let suffix = task.done ? " · 已完成" : ""
                results.append(SearchResultItem(
                    id: "task-\(task.id)",
                    kind: .task,
                    title: task.text,
                    subtitle: "\(displaySearchDate(for: key))\(suffix)",
                    dateKey: key,
                    taskID: task.id,
                    memoID: nil
                ))
            }
        }

        for memo in memos where memo.taskTitle.lowercased().contains(query) || memo.content.lowercased().contains(query) {
            let preview = memo.content.isEmpty ? "" : " · \(String(memo.content.prefix(28)))"
            results.append(SearchResultItem(
                id: "memo-\(memo.id)",
                kind: .memo,
                title: memo.taskTitle,
                subtitle: "\(displaySearchDate(for: memo.date))\(preview)",
                dateKey: memo.date,
                taskID: nil,
                memoID: memo.id
            ))
        }
        return results
    }

    func applySearchSelection(_ result: SearchResultItem) {
        selectedDate = DateKey.date(from: result.dateKey)
        if result.kind == .task {
            selectedTab = .list
            highlightedTaskID = result.taskID
            highlightedMemoID = nil
        } else {
            selectedTab = .memo
            highlightedMemoID = result.memoID
            highlightedTaskID = nil
        }
        showingSearch = false
        persistPreferences()
    }

    func clearHighlightIfNeeded(taskID: String? = nil, memoID: String? = nil) {
        if let taskID, highlightedTaskID == taskID {
            highlightedTaskID = nil
        }
        if let memoID, highlightedMemoID == memoID {
            highlightedMemoID = nil
        }
    }

    func setOpenSwipe(id: String?) {
        openSwipeID = id
    }

    private func apply(snapshot: PersistedSnapshot) {
        todosByDate = Dictionary(uniqueKeysWithValues: snapshot.todos.map { key, value in
            (key, normalizeTasks(value, dateKey: key))
        })
        memos = snapshot.memos.map { memo in
            var copy = memo
            if copy.id.isEmpty {
                copy.id = "memo-\(copy.taskId)-\(Int64(copy.createdAt))"
            }
            return copy
        }
    }

    private func normalizeTasks(_ items: [TaskItem], dateKey: String) -> [TaskItem] {
        items.enumerated().map { offset, item in
            var copy = item
            let fallback = Date().timeIntervalSince1970 * 1000 - Double((items.count - offset) * 1000)
            if copy.id.isEmpty {
                copy.id = "\(dateKey)-\(offset)"
            }
            if copy.createdAt == 0 {
                copy.createdAt = fallback
            }
            if copy.done && copy.completedAt == nil {
                copy.completedAt = copy.createdAt
            }
            return copy
        }
    }

    private func mutateTask(id: String, dateKey: String, mutate: (inout TaskItem) -> Void) {
        guard var list = todosByDate[dateKey], let index = list.firstIndex(where: { $0.id == id }) else { return }
        mutate(&list[index])
        todosByDate[dateKey] = list
        persistAndSync()
    }

    private func persistAndSync() {
        persistLocal()
        let snapshot = PersistedSnapshot(todos: todosByDate, memos: memos)
        Task {
            await saveToCloud(snapshot)
        }
    }

    private func persistLocal() {
        LocalStore.saveSnapshot(PersistedSnapshot(todos: todosByDate, memos: memos))
        persistPreferences()
    }

    private func saveToCloud(_ snapshot: PersistedSnapshot) async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await SyncService.save(baseURL: config.apiBaseURL, syncCode: config.syncCode, snapshot: snapshot)
        } catch {
            syncMessage = "保存到云端失败：\(error.localizedDescription)"
        }
    }

    private func displaySearchDate(for key: String) -> String {
        let date = DateKey.date(from: key)
        if DateKey.isToday(date) {
            return "今天"
        }
        return DateKey.searchFormatter.string(from: date)
    }

    private func taskSort(lhs: TaskItem, rhs: TaskItem) -> Bool {
        if (lhs.pinnedAt != nil) != (rhs.pinnedAt != nil) {
            return lhs.pinnedAt != nil
        }
        if let leftPinned = lhs.pinnedAt, let rightPinned = rhs.pinnedAt, leftPinned != rightPinned {
            return leftPinned > rightPinned
        }
        if lhs.done != rhs.done {
            return !lhs.done
        }
        if !lhs.done {
            return lhs.createdAt > rhs.createdAt
        }
        return (lhs.completedAt ?? 0) > (rhs.completedAt ?? 0)
    }
}

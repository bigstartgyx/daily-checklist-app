import Foundation
import Security
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

enum AIManualInputType: String, CaseIterable, Identifiable, Codable {
    case task
    case memo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .task:
            return "清单"
        case .memo:
            return "备忘"
        }
    }
}

enum AIIntentKind: String, Codable, Equatable {
    case task
    case memo
    case taskWithMemo = "task_with_memo"
    case unknown
}

enum AIRequestState: Equatable {
    case idle
    case loading(String)
    case success(String)
    case failure(String)

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .loading(let message), .success(let message), .failure(let message):
            return message
        }
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

enum MicrophonePermissionState: Equatable {
    case unknown
    case granted
    case denied
}

struct AITaskPayload: Codable, Equatable {
    var text: String
    var dateKey: String
}

struct AIMemoPayload: Codable, Equatable {
    var title: String
    var content: String
    var dateKey: String
}

struct AIIntentResult: Codable, Equatable {
    var transcript: String
    var intent: AIIntentKind
    var task: AITaskPayload?
    var memo: AIMemoPayload?
    var message: String?
    var transcriptRaw: String? = nil
    var transcriptNormalized: String? = nil
    var asrProvider: String? = nil
    var postProcessedBy: String? = nil
}

struct AIServiceSettings: Equatable {
    var baseURL: URL
    var accessToken: String

    static let defaultBaseURL = URL(string: "https://api.deepseek.com")!

    var isConfigured: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct AITextIntentRequest: Encodable {
    var input: String
    var typeHint: String
    var referenceDate: String
    var timeZone: String
}

private struct AIIntentEnvelope: Decodable {
    var ok: Bool?
    var transcript: String?
    var intent: AIIntentKind?
    var task: AITaskPayload?
    var memo: AIMemoPayload?
    var message: String?
    var transcriptRaw: String?
    var transcriptNormalized: String?
    var asrProvider: String?
    var postProcessedBy: String?
}

private struct APIErrorResponse: Decodable {
    var ok: Bool?
    var message: String?
}

private struct OpenAICompatibleMessage: Encodable {
    var role: String
    var content: String
}

private struct OpenAICompatibleRequest: Encodable {
    var model: String
    var temperature: Double
    var messages: [OpenAICompatibleMessage]
}

private struct OpenAICompatibleResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }

        var message: Message
    }

    var choices: [Choice]
}

private struct ProviderErrorEnvelope: Decodable {
    struct Detail: Decodable {
        var message: String?
    }

    var message: String?
    var error: Detail?
}

enum LocalStore {
    private static let snapshotFileName = "bigstart-note-state.json"
    private static let selectedDateKey = "bigstart-note-selected-date"
    private static let selectedTabKey = "bigstart-note-selected-tab"
    private static let aiServiceBaseURLKey = "bigstart-note-ai-base-url"

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

    static func loadAIBaseURL(fallback: URL) -> URL {
        guard let value = UserDefaults.standard.string(forKey: aiServiceBaseURLKey),
              let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return fallback
        }
        return url
    }

    static func saveAIBaseURL(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: aiServiceBaseURLKey)
    }

    private static func snapshotURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BigStartNote", isDirectory: true).appendingPathComponent(snapshotFileName)
    }
}

enum KeychainStore {
    private static let service = "com.bigstart.note"
    private static let aiAccessTokenAccount = "ai-access-token"

    static func loadAIAccessToken() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: aiAccessTokenAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveAIAccessToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: aiAccessTokenAccount
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        var createQuery = query
        createQuery[kSecValueData] = data
        SecItemAdd(createQuery as CFDictionary, nil)
    }

    static func deleteAIAccessToken() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: aiAccessTokenAccount
        ]
        SecItemDelete(query as CFDictionary)
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

enum AIServiceError: LocalizedError {
    case invalidBaseURL
    case unsupportedDirectProvider
    case missingAccessToken
    case missingInput
    case missingConfiguration
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "DeepSeek API 地址无效。"
        case .unsupportedDirectProvider:
            return "这里只支持 DeepSeek 官方直连，请填写 https://api.deepseek.com。"
        case .missingAccessToken:
            return "请先填写 DeepSeek API Key。"
        case .missingInput:
            return "请输入内容。"
        case .missingConfiguration:
            return "请先在“我的”界面填写 DeepSeek API Key。"
        case .invalidResponse:
            return "AI 服务返回了无法识别的数据。"
        case .server(let message):
            return message
        }
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
    @Published var aiSettings: AIServiceSettings
    @Published var aiRequestState: AIRequestState = .idle
    @Published var lastAIResult: AIIntentResult?
    @Published var microphonePermissionState: MicrophonePermissionState = .unknown

    let config: AppConfig
    private var didBootstrap = false

    init(config: AppConfig = .shared) {
        self.config = config
        let storedBaseURL = LocalStore.loadAIBaseURL(fallback: AIServiceSettings.defaultBaseURL)
        let normalizedBaseURL = AppViewModel.normalizedDirectAIBaseURL(storedBaseURL, appBaseURL: config.apiBaseURL)
        if normalizedBaseURL != storedBaseURL {
            LocalStore.saveAIBaseURL(normalizedBaseURL)
        }
        aiSettings = AIServiceSettings(
            baseURL: normalizedBaseURL,
            accessToken: KeychainStore.loadAIAccessToken() ?? ""
        )
    }

    var aiReady: Bool {
        aiSettings.isConfigured
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

    func updateMicrophonePermission(_ state: MicrophonePermissionState) {
        microphonePermissionState = state
    }

    func saveAISettings(baseURLString: String, accessToken: String) throws {
        let settings = try validatedAISettings(baseURLString: baseURLString, accessToken: accessToken, allowEmptyToken: true)
        aiSettings = settings
        LocalStore.saveAIBaseURL(settings.baseURL)
        if settings.accessToken.isEmpty {
            KeychainStore.deleteAIAccessToken()
        } else {
            KeychainStore.saveAIAccessToken(settings.accessToken)
        }
        aiRequestState = .success("AI 服务设置已保存。")
    }

    func testAIConnection(baseURLString: String, accessToken: String) async throws -> String {
        let settings = try validatedAISettings(baseURLString: baseURLString, accessToken: accessToken, allowEmptyToken: false)
        _ = try await performDirectIntentParse(
            input: "明天提醒我测试 DeepSeek 连接",
            typeHint: "memo",
            settings: settings
        )
        return "连接成功，DeepSeek 直连可用。"
    }

    @discardableResult
    func refreshFromCloud(resetDateToToday: Bool, minimumVisibleDuration: TimeInterval = 0) async -> Bool {
        let startedAt = Date()
        let today = DateKey.normalized(Date())
        if resetDateToToday {
            selectedDate = today
            persistPreferences()
        }

        withAnimation(.easeOut(duration: 0.18)) {
            isSyncing = true
        }

        var didSucceed = false

        do {
            let snapshot = try await SyncService.load(baseURL: config.apiBaseURL, syncCode: config.syncCode)
            apply(snapshot: snapshot)
            if resetDateToToday {
                selectedDate = today
            }
            persistLocal()
            didSucceed = true
        } catch {
            if resetDateToToday {
                selectedDate = today
                persistPreferences()
            }
            syncMessage = "从云端同步失败：\(error.localizedDescription)"
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        if minimumVisibleDuration > elapsed {
            let remaining = minimumVisibleDuration - elapsed
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            isSyncing = false
        }

        return didSucceed
    }

    func submitAIText(input: String, typeHint: AIManualInputType) async {
        await submitAIInput(input: input, typeHint: typeHint.rawValue, loadingMessage: "正在解析输入…")
    }

    func submitAITranscript(_ input: String) async {
        await submitAIInput(input: input, typeHint: "auto", loadingMessage: "正在解析语音内容…")
    }

    private func submitAIInput(input: String, typeHint: String, loadingMessage: String) async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            aiRequestState = .failure(AIServiceError.missingInput.localizedDescription)
            return
        }
        guard aiReady else {
            aiRequestState = .failure(AIServiceError.missingConfiguration.localizedDescription)
            return
        }

        aiRequestState = .loading(loadingMessage)

        do {
            let result: AIIntentResult
            result = try await performDirectIntentParse(
                input: trimmed,
                typeHint: typeHint,
                settings: aiSettings
            )
            applyAIIntentResult(result)
        } catch {
            aiRequestState = .failure(error.localizedDescription)
        }
    }

    func submitAIVoice(audioURL: URL, fallbackTranscriber: SpeechTranscriber? = nil) async {
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        guard aiReady else {
            aiRequestState = .failure(AIServiceError.missingConfiguration.localizedDescription)
            return
        }

        do {
            aiRequestState = .loading("正在识别语音…")
            let transcriber = fallbackTranscriber ?? SpeechTranscriber()
            let transcript = try await transcriber.transcribeLocally(audioURL: audioURL)
            await submitAITranscript(transcript)
        } catch {
            aiRequestState = .failure(error.localizedDescription)
        }
    }

    func applyAIIntentResult(_ result: AIIntentResult) {
        lastAIResult = result

        switch result.intent {
        case .task:
            guard let payload = normalizedTaskPayload(result.task) else {
                aiRequestState = .failure(result.message ?? AIServiceError.invalidResponse.localizedDescription)
                return
            }
            let task = appendTask(text: payload.text, dateKey: payload.dateKey)
            selectedDate = DateKey.date(from: payload.dateKey)
            selectedTab = .list
            highlightedTaskID = task.id
            highlightedMemoID = nil
            aiRequestState = .success("已创建清单。")
            persistAndSync()

        case .memo:
            guard let payload = normalizedMemoPayload(result.memo, fallbackDateKey: DateKey.string(from: selectedDate)) else {
                aiRequestState = .failure(result.message ?? AIServiceError.invalidResponse.localizedDescription)
                return
            }
            let memo = appendMemo(
                title: payload.title,
                content: payload.content,
                dateKey: payload.dateKey,
                taskID: "ai-memo-\(UUID().uuidString)"
            )
            selectedDate = DateKey.date(from: payload.dateKey)
            selectedTab = .memo
            highlightedMemoID = memo.id
            highlightedTaskID = nil
            aiRequestState = .success("已创建备忘。")
            persistAndSync()

        case .taskWithMemo:
            guard let taskPayload = normalizedTaskPayload(result.task) else {
                aiRequestState = .failure(result.message ?? AIServiceError.invalidResponse.localizedDescription)
                return
            }
            let createdTask = appendTask(text: taskPayload.text, dateKey: taskPayload.dateKey)
            if let memoPayload = normalizedMemoPayload(result.memo, fallbackDateKey: taskPayload.dateKey) {
                _ = appendMemo(
                    title: memoPayload.title.isEmpty ? createdTask.text : memoPayload.title,
                    content: memoPayload.content,
                    dateKey: memoPayload.dateKey,
                    taskID: createdTask.id
                )
                aiRequestState = .success("已创建清单和备注。")
            } else {
                aiRequestState = .success("已创建清单。")
            }
            selectedDate = DateKey.date(from: taskPayload.dateKey)
            selectedTab = .list
            highlightedTaskID = createdTask.id
            highlightedMemoID = nil
            persistAndSync()

        case .unknown:
            aiRequestState = .failure(result.message ?? "AI 未识别出可创建的清单或备忘。")
        }
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
        struct RankedResult {
            let item: SearchResultItem
            let score: Int
            let dateKey: String
            let timestamp: TimeInterval
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = normalizeSearchText(query)
        let terms = normalizedSearchTerms(from: normalizedQuery)
        guard !terms.isEmpty else { return [] }

        var results: [RankedResult] = []

        for key in todosByDate.keys.sorted(by: >) {
            for task in todosByDate[key] ?? [] {
                let dateLabel = displaySearchDate(for: key)
                guard let match = searchMatch(title: task.text, body: nil, dateLabel: dateLabel, normalizedQuery: normalizedQuery, terms: terms) else {
                    continue
                }

                let meta = [task.pinnedAt != nil ? "置顶" : nil, task.done ? "已完成" : "未完成"]
                    .compactMap { $0 }
                    .joined(separator: " · ")

                results.append(RankedResult(
                    item: SearchResultItem(
                        id: "task-\(task.id)",
                        kind: .task,
                        title: task.text,
                        subtitle: [dateLabel, meta].joined(separator: " · "),
                        dateKey: key,
                        taskID: task.id,
                        memoID: nil
                    ),
                    score: match.score + (task.done ? 0 : 8),
                    dateKey: key,
                    timestamp: task.done ? (task.completedAt ?? task.createdAt) : task.createdAt
                ))
            }
        }

        for memo in memos {
            let dateLabel = displaySearchDate(for: memo.date)
            let memoTitle = memo.taskTitle.isEmpty ? "备忘" : memo.taskTitle
            guard let match = searchMatch(title: memoTitle, body: memo.content, dateLabel: dateLabel, normalizedQuery: normalizedQuery, terms: terms) else {
                continue
            }

            let preview = match.preview ?? String(memo.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(36))
            let subtitleParts = [dateLabel, preview.isEmpty ? nil : preview]

            results.append(RankedResult(
                item: SearchResultItem(
                    id: "memo-\(memo.id)",
                    kind: .memo,
                    title: memoTitle,
                    subtitle: subtitleParts.compactMap { $0 }.joined(separator: " · "),
                    dateKey: memo.date,
                    taskID: nil,
                    memoID: memo.id
                ),
                score: match.score,
                dateKey: memo.date,
                timestamp: memo.createdAt
            ))
        }

        return results
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                if $0.dateKey != $1.dateKey {
                    return $0.dateKey > $1.dateKey
                }
                return $0.timestamp > $1.timestamp
            }
            .map(\.item)
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

    func resetSwipeInteraction() {
        openSwipeID = nil
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

    @discardableResult
    private func appendTask(text: String, dateKey: String) -> TaskItem {
        let item = TaskItem.make(text: text)
        var list = todosByDate[dateKey] ?? []
        list.append(item)
        todosByDate[dateKey] = list
        return item
    }

    @discardableResult
    private func appendMemo(title: String, content: String, dateKey: String, taskID: String) -> MemoItem {
        let item = MemoItem.make(taskId: taskID, date: dateKey, taskTitle: title, content: content)
        memos.insert(item, at: 0)
        return item
    }

    private func normalizedTaskPayload(_ payload: AITaskPayload?) -> AITaskPayload? {
        guard let payload else { return nil }
        let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let key = payload.dateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKey = key.isEmpty ? DateKey.string(from: selectedDate) : key
        return AITaskPayload(text: text, dateKey: normalizedKey)
    }

    private func normalizedMemoPayload(_ payload: AIMemoPayload?, fallbackDateKey: String) -> AIMemoPayload? {
        guard let payload else { return nil }
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = payload.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !content.isEmpty else { return nil }
        let resolvedTitle = title.isEmpty ? "备忘" : title
        let key = payload.dateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIMemoPayload(title: resolvedTitle, content: content, dateKey: key.isEmpty ? fallbackDateKey : key)
    }

    private func validatedAISettings(baseURLString: String, accessToken: String, allowEmptyToken: Bool) throws -> AIServiceSettings {
        let normalizedBaseURLString = normalizeDirectAIBaseURLString(baseURLString)
        guard let url = URL(string: normalizedBaseURLString), let scheme = url.scheme, scheme.hasPrefix("http") else {
            throw AIServiceError.invalidBaseURL
        }
        guard AppViewModel.isSupportedDirectAIBaseURL(url) else {
            throw AIServiceError.unsupportedDirectProvider
        }

        let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !allowEmptyToken && trimmedToken.isEmpty {
            throw AIServiceError.missingAccessToken
        }

        return AIServiceSettings(baseURL: url, accessToken: trimmedToken)
    }

    private func performDirectIntentParse(input: String, typeHint: String, settings: AIServiceSettings) async throws -> AIIntentResult {
        let systemPrompt = [
            "你是一个待办事项与备忘录解析器。",
            "你的任务是把用户输入解析成严格 JSON。",
            "不要闲聊，不要解释，不要输出 JSON 以外的内容。",
            "返回字段必须完整：transcript、intent、task、memo、message。",
            "intent 只能是 task、memo、task_with_memo、unknown。",
            "task 必须包含 text 和 dateKey。",
            "memo 必须包含 title、content、dateKey。",
            "dateKey 必须是 yyyy-MM-dd 格式。",
            "如果 typeHint=task，优先输出 task 或 task_with_memo。",
            "如果 typeHint=memo，优先输出 memo。",
            "如果无法可靠判断，返回 intent=unknown。"
        ].joined(separator: "\n")

        let referenceDate = DateKey.string(from: selectedDate)
        let promptData = try JSONEncoder().encode(AITextIntentRequest(
            input: input,
            typeHint: typeHint,
            referenceDate: referenceDate,
            timeZone: TimeZone.current.identifier
        ))
        let userPrompt = String(data: promptData, encoding: .utf8) ?? input

        let assistantText = try await callOpenAICompatible(
            settings: settings,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        let parsed = try extractIntentResult(from: assistantText, fallbackTranscript: input, fallbackDateKey: referenceDate)
        return parsed
    }

    private func callOpenAICompatible(settings: AIServiceSettings, systemPrompt: String, userPrompt: String) async throws -> String {
        var request = URLRequest(url: directOpenAICompatibleURL(from: settings.baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            OpenAICompatibleRequest(
                model: modelName(for: settings),
                temperature: 0.1,
                messages: [
                    OpenAICompatibleMessage(role: "system", content: systemPrompt),
                    OpenAICompatibleMessage(role: "user", content: userPrompt)
                ]
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIServiceError.server(decodeAPIErrorMessage(from: data) ?? "DeepSeek 请求失败，请检查 API 地址、API Key 和账户额度。")
        }

        let decoded = try JSONDecoder().decode(OpenAICompatibleResponse.self, from: data)
        let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return text
    }

    private func extractIntentResult(from text: String, fallbackTranscript: String, fallbackDateKey: String) throws -> AIIntentResult {
        let jsonObject = try extractJSONObject(from: text)
        let data = try JSONSerialization.data(withJSONObject: jsonObject)
        let envelope = try JSONDecoder().decode(AIIntentEnvelope.self, from: data)
        let transcript = envelope.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = envelope.task.map { payload in
            AITaskPayload(
                text: payload.text.trimmingCharacters(in: .whitespacesAndNewlines),
                dateKey: normalizeDateKey(payload.dateKey, fallback: fallbackDateKey)
            )
        }
        let memo = envelope.memo.map { payload in
            AIMemoPayload(
                title: payload.title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: payload.content.trimmingCharacters(in: .whitespacesAndNewlines),
                dateKey: normalizeDateKey(payload.dateKey, fallback: fallbackDateKey)
            )
        }
        return AIIntentResult(
            transcript: (transcript?.isEmpty == false ? transcript! : fallbackTranscript),
            intent: envelope.intent ?? .unknown,
            task: task,
            memo: memo,
            message: envelope.message
        )
    }

    private func extractJSONObject(from text: String) throws -> Any {
        let candidate: String
        if let fencedRange = text.range(of: "```") {
            let tail = text[fencedRange.upperBound...]
            if let closingRange = tail.range(of: "```") {
                candidate = String(tail[..<closingRange.lowerBound])
            } else {
                candidate = text
            }
        } else {
            candidate = text
        }

        guard let start = candidate.firstIndex(of: "{"),
              let end = candidate.lastIndex(of: "}")
        else {
            throw AIServiceError.invalidResponse
        }

        let jsonString = String(candidate[start...end])
        guard let data = jsonString.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw AIServiceError.invalidResponse
        }
        return object
    }

    private func directOpenAICompatibleURL(from baseURL: URL) -> URL {
        let normalizedBase = normalizedBaseURL(baseURL)
        let path = normalizedBase.path.lowercased()
        if path.hasSuffix("/v1/chat/completions") || path.hasSuffix("/chat/completions") {
            return normalizedBase
        }
        if path.hasSuffix("/v1") {
            return normalizedBase.appendingPathComponent("chat/completions")
        }
        return normalizedBase.appendingPathComponent("v1").appendingPathComponent("chat/completions")
    }

    private func modelName(for settings: AIServiceSettings) -> String {
        _ = settings
        return "deepseek-chat"
    }

    private func normalizedBaseURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.query = nil
        components.fragment = nil
        let trimmedPath = components.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        components.path = trimmedPath
        return components.url ?? url
    }

    private func normalizeDateKey(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = try? NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}$"#)
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        if let regex, regex.firstMatch(in: trimmed, options: [], range: range) != nil {
            return trimmed
        }
        return fallback
    }

    private func decodeAPIErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(APIErrorResponse.self, from: data), let message = decoded.message, !message.isEmpty {
            return message
        }
        if let decoded = try? JSONDecoder().decode(ProviderErrorEnvelope.self, from: data) {
            if let message = decoded.error?.message, !message.isEmpty {
                return message
            }
            if let message = decoded.message, !message.isEmpty {
                return message
            }
        }
        return nil
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

    private func normalizeSearchText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    private func normalizedSearchTerms(from query: String) -> [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func searchMatch(title: String, body: String?, dateLabel: String, normalizedQuery: String, terms: [String]) -> (score: Int, preview: String?)? {
        let normalizedTitle = normalizeSearchText(title)
        let normalizedBody = normalizeSearchText(body ?? "")
        let normalizedDate = normalizeSearchText(dateLabel)
        let combined = [normalizedTitle, normalizedBody, normalizedDate].joined(separator: " ")

        guard terms.allSatisfy({ combined.contains($0) }) else { return nil }

        var score = 0
        if normalizedTitle == normalizedQuery {
            score += 140
        } else if normalizedTitle.hasPrefix(normalizedQuery) {
            score += 110
        } else if normalizedTitle.contains(normalizedQuery) {
            score += 80
        }

        score += terms.filter { normalizedTitle.contains($0) }.count * 20
        score += terms.filter { normalizedBody.contains($0) }.count * 10
        score += terms.filter { normalizedDate.contains($0) }.count * 6

        return (max(score, 1), searchPreview(in: body, terms: terms))
    }

    private func searchPreview(in body: String?, terms: [String]) -> String? {
        guard let body else { return nil }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let nsText = trimmed as NSString
        for term in terms where !term.isEmpty {
            let range = nsText.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
            if range.location != NSNotFound {
                let start = max(0, range.location - 10)
                let end = min(nsText.length, range.location + range.length + 18)
                var preview = nsText.substring(with: NSRange(location: start, length: end - start))
                if start > 0 { preview = "…" + preview }
                if end < nsText.length { preview += "…" }
                return preview
            }
        }

        let preview = String(trimmed.prefix(32))
        return trimmed.count > preview.count ? preview + "…" : preview
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

    private func normalizeDirectAIBaseURLString(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return AIServiceSettings.defaultBaseURL.absoluteString
        }
        if trimmed.contains("://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private static func isSupportedDirectAIBaseURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        return host.contains("deepseek.com")
    }

    private static func normalizedDirectAIBaseURL(_ url: URL, appBaseURL: URL) -> URL {
        if isSupportedDirectAIBaseURL(url) {
            return url
        }

        let storedHost = url.host?.lowercased() ?? ""
        let appHost = appBaseURL.host?.lowercased() ?? ""
        if storedHost == appHost || !storedHost.contains("deepseek.com") {
            return AIServiceSettings.defaultBaseURL
        }
        return url
    }
}

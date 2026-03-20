import Foundation

enum AppEnvironment: String {
    case local
    case staging
    case production
}

enum AppTab: String, CaseIterable, Hashable {
    case list
    case calendar
    case memo
    case ai
    case me
}

struct AppConfig {
    static let shared = AppConfig()

    let environment: AppEnvironment
    let baseURL: URL
    let syncCode: String
    let displayName: String

    private init(bundle: Bundle = .main) {
        let envString = (bundle.object(forInfoDictionaryKey: "APP_ENV") as? String)?.lowercased() ?? AppEnvironment.staging.rawValue
        environment = AppEnvironment(rawValue: envString) ?? .staging

        let baseURLString = (bundle.object(forInfoDictionaryKey: "BaseURL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "https://121.41.198.212/"
        guard let parsed = URL(string: baseURLString) else {
            fatalError("Invalid BaseURL in Info.plist: \(baseURLString)")
        }
        baseURL = parsed

        let syncCodeValue = (bundle.object(forInfoDictionaryKey: "SyncCode") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        syncCode = (syncCodeValue?.isEmpty == false ? syncCodeValue! : "default")
        displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "BigStart Note"
    }

    var apiBaseURL: URL {
        baseURL
    }
}

enum DateKey {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        return calendar
    }()

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let searchFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: normalized(date))
    }

    static func date(from string: String) -> Date {
        if let date = formatter.date(from: string) {
            return normalized(date)
        }
        return normalized(Date())
    }

    static func normalized(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: components.day,
            hour: 12
        )) ?? date
    }

    static func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    static func monthTitle(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }

    static func longTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy年M月d日EEEE"
        return formatter.string(from: date)
    }

    static func memoTitle(dateKey: String, taskTitle: String) -> String {
        let date = self.date(from: dateKey)
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)月\(components.day ?? 0)日 - \(taskTitle)"
    }

    static func shortDateLabel(for date: Date) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }

    static func timeLabel(timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp / 1000))
    }
}

struct TaskItem: Codable, Identifiable, Equatable {
    var id: String
    var text: String
    var done: Bool
    var createdAt: TimeInterval
    var completedAt: TimeInterval?
    var pinnedAt: TimeInterval?

    static func make(text: String) -> TaskItem {
        let now = Date().timeIntervalSince1970 * 1000
        return TaskItem(
            id: String(Int64(now)),
            text: text,
            done: false,
            createdAt: now,
            completedAt: nil,
            pinnedAt: nil
        )
    }
}

struct MemoItem: Codable, Identifiable, Equatable {
    var id: String
    var taskId: String
    var date: String
    var taskTitle: String
    var content: String
    var createdAt: TimeInterval

    static func make(taskId: String, date: String, taskTitle: String, content: String) -> MemoItem {
        let now = Date().timeIntervalSince1970 * 1000
        return MemoItem(
            id: "memo-\(Int64(now))",
            taskId: taskId,
            date: date,
            taskTitle: taskTitle,
            content: content,
            createdAt: now
        )
    }
}

struct TaskSections {
    let pinned: [TaskItem]
    let active: [TaskItem]
    let completed: [TaskItem]
}

struct SearchResultItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case task
        case memo
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let dateKey: String
    let taskID: String?
    let memoID: String?
}

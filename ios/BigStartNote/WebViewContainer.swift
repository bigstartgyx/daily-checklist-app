import SwiftUI
import UIKit

struct ChecklistScreen: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var showingDatePicker = false

    private var selectedKey: String {
        viewModel.dateKey(for: viewModel.selectedDate)
    }

    private var currentSections: TaskSections {
        viewModel.sections(for: selectedKey)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                HStack {
                    Text(viewModel.titleForSelectedDate())
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(BigStartPalette.accent)
                    Spacer()
                    HeaderIconButton(systemImage: "magnifyingglass") {
                        viewModel.showingSearch = true
                    }
                    HeaderIconButton(systemImage: "calendar") {
                        viewModel.setSelectedTab(.calendar)
                    }
                }

                ProgressSummaryView(progress: viewModel.progress(for: viewModel.dateKey(for: viewModel.selectedDate)))

                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("添加新任务", text: $viewModel.taskInput)
                            .textFieldStyle(.plain)
                            .foregroundStyle(BigStartPalette.textPrimary)
                            .tint(BigStartPalette.accent)

                        Button {
                            showingDatePicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(viewModel.inputDateLabel())
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(BigStartPalette.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)

                    Button(action: viewModel.addTask) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(BigStartPalette.accentGradient)
                            .clipShape(Circle())
                            .shadow(color: BigStartPalette.accent.opacity(0.25), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                }

                if currentSections.pinned.isEmpty && currentSections.active.isEmpty && currentSections.completed.isEmpty {
                    BigStartCard {
                        EmptyStateView(title: "暂无任务", description: "先添加一条今天或未来日期的任务。", systemImage: "checklist")
                    }
                } else {
                    TaskSectionView(title: "置顶", items: currentSections.pinned, dateKey: selectedKey, style: .pinned)
                    TaskSectionView(title: "今天", items: currentSections.active, dateKey: selectedKey, style: .active)
                    TaskSectionView(title: "已完成", items: currentSections.completed, dateKey: selectedKey, style: .completed)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 132)
        }
        .scrollDisabled(viewModel.isSwipeDragging)
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker(
                    "选择任务日期",
                    selection: Binding(
                        get: { viewModel.taskTargetDate ?? viewModel.selectedDate },
                        set: { viewModel.taskTargetDate = DateKey.normalized($0) }
                    ),
                    in: DateKey.normalized(Date())...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("目标日期")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("重置") {
                            viewModel.taskTargetDate = nil
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") {
                            showingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

struct CalendarScreen: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var visibleMonth = DateKey.normalized(Date())

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                HStack {
                    Text("日历")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(BigStartPalette.textPrimary)
                    Spacer()
                }

                BigStartCard(
                    background: LinearGradient(
                        colors: [Color(red: 0.97, green: 0.99, blue: 1.0), Color.white],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    borderColor: BigStartPalette.accent.opacity(0.12)
                ) {
                    VStack(spacing: 18) {
                        HStack {
                            CircleIconButton(systemImage: "chevron.left") {
                                visibleMonth = shiftMonth(by: -1)
                            }
                            Spacer()
                            Text(DateKey.monthTitle(for: visibleMonth))
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(BigStartPalette.textPrimary)
                            Spacer()
                            CircleIconButton(systemImage: "chevron.right") {
                                visibleMonth = shiftMonth(by: 1)
                            }
                        }

                        CalendarGridView(
                            month: visibleMonth,
                            selectedDate: viewModel.selectedDate,
                            progress: { key in viewModel.progress(for: key) },
                            hasMemo: { key in viewModel.memos.contains(where: { $0.date == key }) },
                            onSelect: { date in
                                viewModel.setSelectedDate(date)
                            }
                        )
                    }
                }

                let key = viewModel.dateKey(for: viewModel.selectedDate)
                let progress = viewModel.progress(for: key)
                let sections = viewModel.sections(for: key)

                BigStartCard(
                    background: LinearGradient(
                        colors: [Color(red: 0.92, green: 0.96, blue: 1.0), Color(red: 0.98, green: 0.99, blue: 1.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    borderColor: BigStartPalette.accent.opacity(0.16)
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(DateKey.longTitle(for: viewModel.selectedDate))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BigStartPalette.textPrimary)
                            Spacer()
                            CompactProgressPill(progress: progress)
                        }

                        HStack(spacing: 10) {
                            CalendarSummaryStat(label: "全部", value: progress.total, tint: BigStartPalette.accent.opacity(0.12))
                            CalendarSummaryStat(label: "未完成", value: sections.active.count, tint: BigStartPalette.accent.opacity(0.1))
                            CalendarSummaryStat(label: "已完成", value: sections.completed.count, tint: Color.green.opacity(0.12))
                        }

                        if progress.total == 0 {
                            Text("下面保留与清单一致的三区结构，方便直接在日历里管理任务。")
                                .font(.subheadline)
                                .foregroundStyle(BigStartPalette.textSecondary)
                        }
                    }
                }

                TaskSectionView(
                    title: "置顶",
                    items: sections.pinned,
                    dateKey: key,
                    style: .pinned,
                    emptyText: "当天暂无置顶任务"
                )
                TaskSectionView(
                    title: "未完成",
                    items: sections.active,
                    dateKey: key,
                    style: .active,
                    emptyText: "当天暂无未完成任务"
                )
                TaskSectionView(
                    title: "已完成",
                    items: sections.completed,
                    dateKey: key,
                    style: .completed,
                    emptyText: "当天暂无已完成任务"
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 132)
            .onAppear {
                visibleMonth = viewModel.selectedDate
            }
        }
        .scrollDisabled(viewModel.isSwipeDragging)
    }

    private func shiftMonth(by offset: Int) -> Date {
        DateKey.calendar.date(byAdding: .month, value: offset, to: visibleMonth) ?? visibleMonth
    }
}

struct MemoScreen: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("备忘录")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(BigStartPalette.textPrimary)
                    Text("\(viewModel.memos.count) 条记录")
                        .font(.subheadline)
                        .foregroundStyle(BigStartPalette.textSecondary)
                }

                Button {
                    viewModel.openNewMemo()
                } label: {
                    Text("+ 新建备忘录")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(BigStartPalette.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: BigStartPalette.accent.opacity(0.25), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)

                if viewModel.memosSorted().isEmpty {
                    BigStartCard {
                        EmptyStateView(title: "暂无备忘录", description: "可以从任务右滑添加，也可以直接在这里新建。", systemImage: "note.text")
                    }
                } else {
                    ForEach(viewModel.memosSorted()) { memo in
                        MemoRowView(memo: memo, highlighted: viewModel.highlightedMemoID == memo.id)
                        .task {
                            if viewModel.highlightedMemoID == memo.id {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                viewModel.clearHighlightIfNeeded(memoID: memo.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 132)
        }
        .scrollDisabled(viewModel.isSwipeDragging)
    }
}

struct PlaceholderScreen: View {
    let title: String
    let description: String
    let systemImage: String

    var body: some View {
        ScrollView {
            EmptyStateView(title: title, description: description, systemImage: systemImage)
                .padding(.top, 120)
                .padding(.bottom, 132)
                .padding(.horizontal, 20)
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let description: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(BigStartPalette.textSecondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(BigStartPalette.textPrimary)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(BigStartPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

struct ProgressSummaryView: View {
    let progress: (done: Int, total: Int, percent: Double)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(red: 0.90, green: 0.90, blue: 0.92))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(BigStartPalette.accentGradient)
                        .frame(width: max(0, geo.size.width * progress.percent))
                }
            }
            .frame(height: 6)

            Text("\(progress.done) / \(progress.total) 已完成")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BigStartPalette.textSecondary)
        }
    }
}

enum BigStartSectionStyle {
    case pinned
    case active
    case completed

    var background: LinearGradient {
        switch self {
        case .pinned:
            return LinearGradient(colors: [Color(red: 1.0, green: 0.97, blue: 0.91), .white], startPoint: .top, endPoint: .bottom)
        case .active:
            return LinearGradient(colors: [Color(red: 0.93, green: 0.96, blue: 1.0), .white], startPoint: .top, endPoint: .bottom)
        case .completed:
            return LinearGradient(colors: [Color(red: 0.94, green: 0.99, blue: 0.96), .white], startPoint: .top, endPoint: .bottom)
        }
    }

    var borderColor: Color {
        switch self {
        case .pinned: return Color.orange.opacity(0.16)
        case .active: return BigStartPalette.accent.opacity(0.14)
        case .completed: return Color.green.opacity(0.14)
        }
    }
}

struct TaskSectionView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let title: String
    let items: [TaskItem]
    let dateKey: String
    let style: BigStartSectionStyle
    var emptyText: String? = nil

    var body: some View {
        if !items.isEmpty || emptyText != nil {
            BigStartCard(background: style.background, borderColor: style.borderColor) {
                VStack(spacing: 8) {
                    HStack {
                        Text(title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(BigStartPalette.textPrimary)
                        Spacer()
                        Text("\(items.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BigStartPalette.textSecondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)

                    if items.isEmpty {
                        Text(emptyText ?? "暂无任务")
                            .font(.subheadline)
                            .foregroundStyle(BigStartPalette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 14)
                    } else {
                        ForEach(items) { task in
                            TaskRowView(task: task, dateKey: dateKey, highlighted: viewModel.highlightedTaskID == task.id)
                                .task {
                                    if viewModel.highlightedTaskID == task.id {
                                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                                        viewModel.clearHighlightIfNeeded(taskID: task.id)
                                    }
                                }
                        }
                    }
                }
            }
        }
    }
}

struct CalendarSummaryStat: View {
    let label: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BigStartPalette.textSecondary)
            Text("\(value)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(BigStartPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint)
        )
    }
}

struct TaskRowView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let task: TaskItem
    let dateKey: String
    let highlighted: Bool

    var body: some View {
        BigStartSwipeRow(
            swipeID: "task-\(dateKey)-\(task.id)",
            leadingWidth: 164,
            trailingWidth: 164,
            interactionProfile: .task,
            onTap: {
                if !task.done {
                    viewModel.openTaskEditor(task: task, dateKey: dateKey)
                }
            },
            content: {
                HStack(spacing: 14) {
                    Button {
                        viewModel.toggleDone(task: task, dateKey: dateKey)
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(task.done ? Color.clear : Color(red: 0.90, green: 0.90, blue: 0.92), lineWidth: 2)
                                .frame(width: 26, height: 26)
                            if task.done {
                                Circle()
                                    .fill(BigStartPalette.accentGradient)
                                    .frame(width: 26, height: 26)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Text(task.text)
                            .font(.system(size: 16, weight: .medium))
                            .strikethrough(task.done)
                            .foregroundStyle(task.done ? BigStartPalette.textSecondary : BigStartPalette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)

                        if task.pinnedAt != nil {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if viewModel.hasMemo(for: task, dateKey: dateKey) {
                            Image(systemName: "note.text")
                                .font(.caption)
                                .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.29))
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(highlighted ? BigStartPalette.accent : Color.clear, lineWidth: 2)
                )
            },
            leadingActions: {
                HStack(spacing: 10) {
                    SwipeActionPill(systemImage: "note.text.badge.plus", tint: .blue) {
                        viewModel.setOpenSwipe(id: nil)
                        viewModel.openMemoEditorForTask(task: task, dateKey: dateKey)
                    }
                    SwipeActionPill(systemImage: "pin.fill", tint: .orange) {
                        viewModel.setOpenSwipe(id: nil)
                        viewModel.togglePin(task: task, dateKey: dateKey)
                    }
                }
            },
            trailingActions: {
                HStack(spacing: 10) {
                    SwipeActionPill(systemImage: "calendar", tint: .green) {
                        viewModel.setOpenSwipe(id: nil)
                        viewModel.openMoveEditor(task: task, dateKey: dateKey)
                    }
                    SwipeActionPill(systemImage: "trash.fill", tint: .red) {
                        viewModel.setOpenSwipe(id: nil)
                        viewModel.deleteTask(task: task, dateKey: dateKey)
                    }
                }
            }
        )
    }
}

struct CalendarTaskRowView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let task: TaskItem
    let dateKey: String

    var body: some View {
        BigStartSwipeRow(
            swipeID: "calendar-task-\(dateKey)-\(task.id)",
            leadingWidth: 164,
            trailingWidth: 164,
            interactionProfile: .task,
            onTap: {
                if !task.done {
                    viewModel.openTaskEditor(task: task, dateKey: dateKey)
                }
            },
            content: {
                HStack(spacing: 12) {
                    Button {
                        viewModel.toggleDone(task: task, dateKey: dateKey)
                    } label: {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(task.done ? BigStartPalette.accent : .secondary)
                    }
                    .buttonStyle(.plain)

                    Text(task.text)
                        .font(.system(size: 16, weight: .medium))
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? BigStartPalette.textSecondary : BigStartPalette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)

                    if task.pinnedAt != nil {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.orange)
                    }
                    if viewModel.hasMemo(for: task, dateKey: dateKey) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.yellow)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            },
            leadingActions: {
                HStack(spacing: 10) {
                    SwipeActionPill(systemImage: "note.text.badge.plus", tint: .blue) {
                        viewModel.setOpenSwipe(id: nil)
                        viewModel.openMemoEditorForTask(task: task, dateKey: dateKey)
                    }
                    SwipeActionPill(systemImage: "pin.fill", tint: .orange) {
                        viewModel.setOpenSwipe(id: nil)
                        viewModel.togglePin(task: task, dateKey: dateKey)
                    }
                }
            },
            trailingActions: {
                HStack(spacing: 10) {
                    SwipeActionPill(systemImage: "calendar", tint: .green) {
                        viewModel.setOpenSwipe(id: nil)
                        viewModel.openMoveEditor(task: task, dateKey: dateKey)
                    }
                    SwipeActionPill(systemImage: "trash.fill", tint: .red) {
                        viewModel.setOpenSwipe(id: nil)
                        viewModel.deleteTask(task: task, dateKey: dateKey)
                    }
                }
            }
        )
    }
}

struct TaskSummaryRow: View {
    let task: TaskItem
    let hasMemo: Bool

    var body: some View {
        HStack {
            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.done ? BigStartPalette.accent : .secondary)
            Text(task.text)
                .strikethrough(task.done)
                .foregroundStyle(task.done ? BigStartPalette.textSecondary : BigStartPalette.textPrimary)
            Spacer()
            if task.pinnedAt != nil {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.orange)
            }
            if hasMemo {
                Image(systemName: "note.text")
                    .foregroundStyle(.yellow)
            }
        }
    }
}

struct MemoRowView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let memo: MemoItem
    let highlighted: Bool

    var body: some View {
        BigStartSwipeRow(
            swipeID: "memo-\(memo.id)",
            leadingWidth: 0,
            trailingWidth: 92,
            interactionProfile: .memo,
            onTap: {
                viewModel.openMemoEditor(memo)
            },
            content: {
                BigStartCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(DateKey.memoTitle(dateKey: memo.date, taskTitle: memo.taskTitle))
                            .font(.headline)
                            .foregroundStyle(BigStartPalette.textPrimary)
                        Text(memo.content.isEmpty ? "暂无内容" : memo.content)
                            .font(.subheadline)
                            .foregroundStyle(BigStartPalette.textSecondary)
                            .lineLimit(3)
                        Text("• \(DateKey.timeLabel(timestamp: memo.createdAt))")
                            .font(.caption)
                            .foregroundStyle(BigStartPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(highlighted ? BigStartPalette.accent : Color.clear, lineWidth: 2)
                    )
                }
            },
            leadingActions: {
                EmptyView()
            },
            trailingActions: {
                HStack(spacing: 10) {
                    SwipeActionPill(systemImage: "trash.fill", tint: .red) {
                        viewModel.setOpenSwipe(id: nil)
                        viewModel.deleteMemo(memo)
                    }
                }
            }
        )
    }
}

struct CalendarGridView: View {
    let month: Date
    let selectedDate: Date
    let progress: (String) -> (done: Int, total: Int, percent: Double)
    let hasMemo: (String) -> Bool
    let onSelect: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .foregroundStyle(BigStartPalette.textSecondary)
                    .frame(maxWidth: .infinity)
            }

            ForEach(days(), id: \.self) { entry in
                if let date = entry {
                    let key = DateKey.string(from: date)
                    let dayProgress = progress(key)
                    let isSelected = DateKey.isSameDay(date, selectedDate)
                    Button {
                        onSelect(date)
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(DateKey.calendar.component(.day, from: date))")
                                .font(.subheadline.weight(isSelected ? .bold : .regular))
                            HStack(spacing: 4) {
                                if dayProgress.done > 0 {
                                    Circle().fill(Color.green).frame(width: 6, height: 6)
                                }
                                if dayProgress.total - dayProgress.done > 0 {
                                    Circle().fill(Color.red).frame(width: 6, height: 6)
                                }
                                if hasMemo(key) {
                                    Circle().fill(Color.yellow).frame(width: 6, height: 6)
                                }
                            }
                            .frame(height: 8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 8)
                        .background(isSelected ? BigStartPalette.accent : Color.white.opacity(0.82))
                        .foregroundStyle(isSelected ? .white : BigStartPalette.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(height: 60)
                }
            }
        }
    }

    private func days() -> [Date?] {
        let startOfMonth = DateKey.calendar.date(from: DateKey.calendar.dateComponents([.year, .month], from: month)) ?? month
        let dayRange = DateKey.calendar.range(of: .day, in: .month, for: startOfMonth) ?? 1..<2
        let firstWeekday = DateKey.calendar.component(.weekday, from: startOfMonth)
        var values = Array(repeating: Optional<Date>.none, count: firstWeekday - 1)
        values.append(contentsOf: dayRange.compactMap { day in
            DateKey.calendar.date(byAdding: .day, value: day - 1, to: startOfMonth)
        })
        while values.count % 7 != 0 {
            values.append(nil)
        }
        return values
    }
}

struct SearchSheetView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyStateView(title: "搜索", description: "输入关键词搜索清单和备忘录。", systemImage: "magnifyingglass")
                } else if viewModel.searchResults().isEmpty {
                    EmptyStateView(title: "未找到相关内容", description: "换个关键词试试。", systemImage: "magnifyingglass")
                } else {
                    if !viewModel.searchResults().filter({ $0.kind == .task }).isEmpty {
                        Section("清单") {
                            ForEach(viewModel.searchResults().filter { $0.kind == .task }) { result in
                                Button {
                                    viewModel.applySearchSelection(result)
                                    dismiss()
                                } label: {
                                    SearchResultRow(result: result)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !viewModel.searchResults().filter({ $0.kind == .memo }).isEmpty {
                        Section("备忘录") {
                            ForEach(viewModel.searchResults().filter { $0.kind == .memo }) { result in
                                Button {
                                    viewModel.applySearchSelection(result)
                                    dismiss()
                                } label: {
                                    SearchResultRow(result: result)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("搜索")
            .searchable(text: $viewModel.searchText, prompt: "搜索清单和备忘录")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.title)
                .font(.headline)
                .foregroundStyle(BigStartPalette.textPrimary)
            Text(result.subtitle)
                .font(.caption)
                .foregroundStyle(BigStartPalette.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

enum BigStartPalette {
    static let accent = Color(red: 0.10, green: 0.45, blue: 0.91)
    static let textPrimary = Color(red: 0.15, green: 0.17, blue: 0.22)
    static let textSecondary = Color(red: 0.49, green: 0.53, blue: 0.60)
    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.45, blue: 0.91),
            Color(red: 0.26, green: 0.52, blue: 0.96)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct HeaderIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.gray.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct CircleIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BigStartPalette.textPrimary)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct BigStartCard<Content: View>: View {
    var background: LinearGradient = LinearGradient(colors: [Color.white, Color.white], startPoint: .top, endPoint: .bottom)
    var borderColor: Color = Color.black.opacity(0.04)
    @ViewBuilder let content: Content

    init(background: LinearGradient = LinearGradient(colors: [Color.white, Color.white], startPoint: .top, endPoint: .bottom), borderColor: Color = Color.black.opacity(0.04), @ViewBuilder content: () -> Content) {
        self.background = background
        self.borderColor = borderColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 10)
    }
}

struct SwipeActionPill: View {
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 48)
                .background(tint)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: tint.opacity(0.22), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct BigStartSwipeRow<Content: View, LeadingActions: View, TrailingActions: View>: View {
    enum InteractionProfile {
        case task
        case memo

        func openThreshold(for width: CGFloat) -> CGFloat {
            switch self {
            case .task:
                return min(width, max(112, width * 0.68))
            case .memo:
                return min(width, max(64, width * 0.7))
            }
        }

        func closeThreshold(for width: CGFloat) -> CGFloat {
            switch self {
            case .task:
                return width * 0.76
            case .memo:
                return min(width, max(72, width * 0.78))
            }
        }

        func switchThreshold(for width: CGFloat) -> CGFloat {
            switch self {
            case .task:
                return min(width, max(140, width * 0.85))
            case .memo:
                return width
            }
        }

        var closedActivationDistance: CGFloat {
            18
        }

        var openActivationDistance: CGFloat {
            switch self {
            case .task:
                return 12
            case .memo:
                return 10
            }
        }

        var closedDominanceRatio: CGFloat {
            1.45
        }

        var openDominanceRatio: CGFloat {
            switch self {
            case .task:
                return 1.2
            case .memo:
                return 1.12
            }
        }
    }

    @EnvironmentObject private var viewModel: AppViewModel
    let swipeID: String
    let leadingWidth: CGFloat
    let trailingWidth: CGFloat
    let interactionProfile: InteractionProfile
    let onTap: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let leadingActions: LeadingActions
    @ViewBuilder let trailingActions: TrailingActions

    @State private var settledOffset: CGFloat = 0
    // Keep drag state in @State so SwiftUI does not auto-reset it to zero at
    // gesture end, which causes the visible "snap back then open" rebound.
    @State private var dragTranslation: CGFloat = 0
    @State private var dragBaseOffset: CGFloat = 0
    @State private var isDraggingHorizontally = false

    private var currentOffset: CGFloat {
        let raw = isDraggingHorizontally ? (dragBaseOffset + dragTranslation) : settledOffset
        return min(max(raw, -trailingWidth), leadingWidth)
    }

    private var actionsAreOpen: Bool {
        settledOffset != 0 && !isDraggingHorizontally
    }

    private var settleAnimation: Animation {
        .easeOut(duration: 0.16)
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if leadingWidth > 0 {
                    HStack(spacing: 10) {
                        leadingActions
                    }
                    .frame(width: leadingWidth, alignment: .trailing)
                    .padding(.trailing, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.clear, Color.white.opacity(0.54), Color.white.opacity(0.96)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(currentOffset > 0 ? 1 : 0)
                    .allowsHitTesting(currentOffset > 0)
                    .zIndex(currentOffset > 0 ? 2 : 0)
                }

                Spacer(minLength: 0)

                if trailingWidth > 0 {
                    HStack(spacing: 10) {
                        trailingActions
                    }
                    .frame(width: trailingWidth, alignment: .leading)
                    .padding(.leading, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.clear, Color.white.opacity(0.54), Color.white.opacity(0.96)],
                            startPoint: .trailing,
                            endPoint: .leading
                        )
                    )
                    .opacity(currentOffset < 0 ? 1 : 0)
                    .allowsHitTesting(currentOffset < 0)
                    .zIndex(currentOffset < 0 ? 2 : 0)
                }
            }

            content
                .offset(x: currentOffset)
                .contentShape(Rectangle())
                .allowsHitTesting(!actionsAreOpen)
                .onTapGesture {
                    if settledOffset != 0 {
                        withAnimation(settleAnimation) {
                            settledOffset = 0
                        }
                    } else {
                        onTap()
                    }
                }
                .zIndex(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if actionsAreOpen {
                closeActions()
            }
        }
        .simultaneousGesture(dragGesture)
        .animation(settleAnimation, value: settledOffset)
        .onChange(of: viewModel.openSwipeID) { openID in
            if openID != swipeID && settledOffset != 0 {
                closeActions()
            }
        }
        .onDisappear {
            if isDraggingHorizontally {
                viewModel.setSwipeDragging(false)
            }
            if viewModel.openSwipeID == swipeID {
                viewModel.setOpenSwipe(id: nil)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                if !isDraggingHorizontally {
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    let activationDistance = settledOffset == 0 ? interactionProfile.closedActivationDistance : interactionProfile.openActivationDistance
                    let dominanceRatio = settledOffset == 0 ? interactionProfile.closedDominanceRatio : interactionProfile.openDominanceRatio
                    guard horizontal >= activationDistance else { return }
                    guard horizontal > max(vertical * dominanceRatio, vertical + 10) else { return }
                    isDraggingHorizontally = true
                    dragBaseOffset = settledOffset
                    viewModel.setSwipeDragging(true)
                    if viewModel.openSwipeID != nil && viewModel.openSwipeID != swipeID {
                        viewModel.setOpenSwipe(id: nil)
                    }
                }

                dragTranslation = value.translation.width
            }
            .onEnded { value in
                guard isDraggingHorizontally else { return }

                let actual = min(max(dragBaseOffset + value.translation.width, -trailingWidth), leadingWidth)
                let projected = dragBaseOffset + value.predictedEndTranslation.width
                let proposed = min(max(projected, -trailingWidth), leadingWidth)
                let leadingOpenThreshold = interactionProfile.openThreshold(for: leadingWidth)
                let trailingOpenThreshold = interactionProfile.openThreshold(for: trailingWidth)
                let leadingCloseThreshold = interactionProfile.closeThreshold(for: leadingWidth)
                let trailingCloseThreshold = interactionProfile.closeThreshold(for: trailingWidth)
                let leadingSwitchThreshold = interactionProfile.switchThreshold(for: leadingWidth)
                let trailingSwitchThreshold = interactionProfile.switchThreshold(for: trailingWidth)

                let targetOffset: CGFloat
                let openSwipeID: String?

                if dragBaseOffset > 0 {
                    if trailingWidth > 0 && actual < -trailingSwitchThreshold {
                        targetOffset = -trailingWidth
                        openSwipeID = swipeID
                    } else if actual < leadingCloseThreshold {
                        targetOffset = 0
                        openSwipeID = nil
                    } else {
                        targetOffset = leadingWidth
                        openSwipeID = swipeID
                    }
                } else if dragBaseOffset < 0 {
                    if leadingWidth > 0 && actual > leadingSwitchThreshold {
                        targetOffset = leadingWidth
                        openSwipeID = swipeID
                    } else if actual > -trailingCloseThreshold {
                        targetOffset = 0
                        openSwipeID = nil
                    } else {
                        targetOffset = -trailingWidth
                        openSwipeID = swipeID
                    }
                } else if proposed > leadingOpenThreshold && leadingWidth > 0 {
                    targetOffset = leadingWidth
                    openSwipeID = swipeID
                } else if proposed < -trailingOpenThreshold && trailingWidth > 0 {
                    targetOffset = -trailingWidth
                    openSwipeID = swipeID
                } else {
                    targetOffset = 0
                    openSwipeID = nil
                }

                withAnimation(settleAnimation) {
                    settledOffset = targetOffset
                    dragTranslation = 0
                    isDraggingHorizontally = false
                }

                dragBaseOffset = 0
                viewModel.setSwipeDragging(false)

                if openSwipeID == swipeID {
                    viewModel.setOpenSwipe(id: swipeID)
                } else if viewModel.openSwipeID == swipeID {
                    viewModel.setOpenSwipe(id: nil)
                }
            }
    }

    private func closeActions() {
        withAnimation(settleAnimation) {
            settledOffset = 0
            dragTranslation = 0
            isDraggingHorizontally = false
        }
        dragBaseOffset = 0
        viewModel.setSwipeDragging(false)
        if viewModel.openSwipeID == swipeID {
            viewModel.setOpenSwipe(id: nil)
        }
    }
}

struct CompactProgressPill: View {
    let progress: (done: Int, total: Int, percent: Double)

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.08)).frame(width: 64, height: 6)
                Capsule().fill(BigStartPalette.accentGradient).frame(width: max(0, 64 * progress.percent), height: 6)
            }
            Text("\(progress.done)/\(progress.total)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BigStartPalette.textSecondary)
        }
    }
}

struct TaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var text: String
    let draft: TaskDraft

    init(draft: TaskDraft) {
        self.draft = draft
        _text = State(initialValue: draft.task.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("任务内容", text: $text, axis: .vertical)
            }
            .navigationTitle("编辑任务")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        viewModel.updateTask(draft.task, dateKey: draft.dateKey, text: text)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct MemoEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var title: String
    @State private var content: String
    let draft: MemoDraft

    init(draft: MemoDraft) {
        self.draft = draft
        _title = State(initialValue: draft.title)
        _content = State(initialValue: draft.content)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("备忘标题", text: $title)
                TextField("备忘内容", text: $content, axis: .vertical)
                    .lineLimit(6, reservesSpace: true)
            }
            .navigationTitle(draft.existingMemoID == nil ? "新建备忘录" : "编辑备忘录")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        viewModel.saveMemo(MemoDraft(
                            existingMemoID: draft.existingMemoID,
                            taskID: draft.taskID,
                            dateKey: draft.dateKey,
                            title: title,
                            content: content
                        ))
                        dismiss()
                    }
                }
            }
        }
    }
}

struct MoveTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var date: Date
    let draft: TaskMoveDraft

    init(draft: TaskMoveDraft) {
        self.draft = draft
        _date = State(initialValue: DateKey.date(from: draft.fromDateKey))
    }

    var body: some View {
        NavigationStack {
            DatePicker("更改日期", selection: $date, in: DateKey.normalized(Date())..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("更改日期")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("保存") {
                            viewModel.moveTask(task: draft.task, from: draft.fromDateKey, to: date)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

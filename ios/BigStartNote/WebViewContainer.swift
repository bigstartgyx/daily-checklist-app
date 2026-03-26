import AVFoundation
import Speech
import SwiftUI
import UIKit

struct ChecklistScreen: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var showingDatePicker = false
    @State private var inputPickerMonth = DateKey.normalized(Date())
    @FocusState private var isTaskInputFocused: Bool
    @State private var pinnedExpanded = true
    @State private var activeExpanded = true
    @State private var completedExpanded = false
    @State private var refreshIndicatorVisible = false
    @State private var refreshIndicatorTask: Task<Void, Never>?

    private var selectedKey: String {
        viewModel.dateKey(for: viewModel.selectedDate)
    }

    private var currentSections: TaskSections {
        viewModel.sections(for: selectedKey)
    }

    private var showsCompletedSection: Bool {
        if !currentSections.completed.isEmpty {
            return true
        }
        guard let highlightedTaskID = viewModel.highlightedTaskID else { return false }
        return currentSections.completed.contains { $0.id == highlightedTaskID }
    }

    private var activeSectionTitle: String {
        DateKey.isToday(viewModel.selectedDate) ? "今天" : "未完成"
    }

    private var activeSectionEmptyText: String {
        DateKey.isToday(viewModel.selectedDate) ? "今天暂无任务" : "当天暂无未完成任务"
    }

    private func taskRowID(_ id: String) -> String {
        "task-\(id)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                List {
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
            .bigStartListRow(top: 20, bottom: 8)

            ProgressSummaryView(progress: viewModel.progress(for: viewModel.dateKey(for: viewModel.selectedDate)))
                .bigStartListRow(bottom: 10)

            HStack {
                HStack(spacing: 8) {
                    TextField("添加新任务", text: $viewModel.taskInput)
                        .textFieldStyle(.plain)
                        .foregroundStyle(BigStartPalette.textPrimary)
                        .tint(BigStartPalette.accent)
                        .focused($isTaskInputFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isTaskInputFocused = false
                        }

                    Button {
                        isTaskInputFocused = false
                        let baseDate = viewModel.taskTargetDate ?? viewModel.selectedDate
                        inputPickerMonth = DateKey.calendar.date(
                            from: DateKey.calendar.dateComponents([.year, .month], from: baseDate)
                        ) ?? DateKey.normalized(baseDate)
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

                Button {
                    isTaskInputFocused = false
                    viewModel.addTask()
                    showingDatePicker = false
                } label: {
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
            .bigStartListRow(bottom: 12)

            if currentSections.pinned.isEmpty && currentSections.active.isEmpty && currentSections.completed.isEmpty {
                BigStartCard {
                    EmptyStateView(title: "暂无任务", description: "先添加一条今天或未来日期的任务。", systemImage: "checklist")
                }
                .bigStartListRow(bottom: 12)
            }

            CollapsibleTaskListSection(
                title: "置顶",
                count: currentSections.pinned.count,
                style: .pinned,
                emptyText: "暂无置顶任务",
                isExpanded: $pinnedExpanded,
                topSpacing: 4,
                items: currentSections.pinned
            ) { task in
                TaskRowView(
                    task: task,
                    dateKey: selectedKey,
                    highlighted: viewModel.highlightedTaskID == task.id,
                    sectionStyle: .pinned
                )
                .id(taskRowID(task.id))
                .task {
                    if viewModel.highlightedTaskID == task.id {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        viewModel.clearHighlightIfNeeded(taskID: task.id)
                    }
                }
            }

            CollapsibleTaskListSection(
                title: activeSectionTitle,
                count: currentSections.active.count,
                style: .active,
                emptyText: activeSectionEmptyText,
                isExpanded: $activeExpanded,
                topSpacing: 10,
                items: currentSections.active
            ) { task in
                TaskRowView(
                    task: task,
                    dateKey: selectedKey,
                    highlighted: viewModel.highlightedTaskID == task.id,
                    sectionStyle: .active
                )
                .id(taskRowID(task.id))
                .task {
                    if viewModel.highlightedTaskID == task.id {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        viewModel.clearHighlightIfNeeded(taskID: task.id)
                    }
                }
            }

            if showsCompletedSection {
                CollapsibleTaskListSection(
                    title: "已完成",
                    count: currentSections.completed.count,
                    style: .completed,
                    emptyText: "暂无已完成任务",
                    isExpanded: $completedExpanded,
                    topSpacing: 10,
                    items: currentSections.completed
                ) { task in
                    TaskRowView(
                        task: task,
                        dateKey: selectedKey,
                        highlighted: viewModel.highlightedTaskID == task.id,
                        sectionStyle: .completed
                    )
                    .id(taskRowID(task.id))
                    .task {
                        if viewModel.highlightedTaskID == task.id {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            viewModel.clearHighlightIfNeeded(taskID: task.id)
                        }
                    }
                }
            }

                Color.clear
                    .frame(height: 120)
                    .bigStartListRow()
                }
                if refreshIndicatorVisible {
                    RefreshIndicatorView()
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                        .padding(.top, 12)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollDismissesKeyboard(.immediately)
            .refreshable {
                isTaskInputFocused = false
                showingDatePicker = false
                await viewModel.refreshFromCloud(
                    resetDateToToday: true,
                    minimumVisibleDuration: 0.85
                )
            }
            .onChange(of: viewModel.isSyncing) { syncing in
                if syncing {
                    showRefreshIndicator()
                } else {
                    hideRefreshIndicator()
                }
            }
            .onDisappear {
                refreshIndicatorTask?.cancel()
            }
            .sheet(isPresented: $showingDatePicker) {
                NavigationStack {
                    TaskInputDatePickerPanel(
                        visibleMonth: $inputPickerMonth,
                        selectedDate: viewModel.taskTargetDate ?? viewModel.selectedDate,
                        minimumDate: DateKey.normalized(Date())
                    ) { date in
                        viewModel.taskTargetDate = DateKey.normalized(date)
                        showingDatePicker = false
                    }
                    .padding()
                    .navigationTitle("目标日期")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("重置") {
                                viewModel.taskTargetDate = nil
                                inputPickerMonth = DateKey.normalized(viewModel.selectedDate)
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
            .onAppear {
                resetSectionStates()
                guard let id = viewModel.highlightedTaskID else { return }
                revealTaskResult(id: id, proxy: proxy)
            }
            .onChange(of: selectedKey) { _ in
                resetSectionStates()
            }
            .onChange(of: viewModel.highlightedTaskID) { id in
                guard let id else { return }
                revealTaskResult(id: id, proxy: proxy)
            }
        }
    }

    private func revealTaskResult(id: String, proxy: ScrollViewProxy) {
        if currentSections.pinned.contains(where: { $0.id == id }) {
            pinnedExpanded = true
        } else if currentSections.active.contains(where: { $0.id == id }) {
            activeExpanded = true
        } else if currentSections.completed.contains(where: { $0.id == id }) {
            completedExpanded = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            withAnimation(.easeInOut(duration: 0.28)) {
                proxy.scrollTo(taskRowID(id), anchor: .center)
            }
        }
    }

    private func showRefreshIndicator() {
        refreshIndicatorTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            refreshIndicatorVisible = true
        }
    }

    private func hideRefreshIndicator() {
        refreshIndicatorTask?.cancel()
        refreshIndicatorTask = Task {
            try? await Task.sleep(nanoseconds: 420_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    refreshIndicatorVisible = false
                }
            }
        }
    }

    private struct RefreshIndicatorView: View {
        var body: some View {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: BigStartPalette.accent))
                    .scaleEffect(0.85)
                Text("正在刷新")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BigStartPalette.textPrimary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 48)
        }
    }

    private func resetSectionStates() {
        pinnedExpanded = true
        activeExpanded = true
        completedExpanded = false
    }
}

struct CalendarScreen: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var visibleMonth = DateKey.normalized(Date())
    @State private var pinnedExpanded = false
    @State private var activeExpanded = true
    @State private var completedExpanded = false

    private var activeSectionTitle: String {
        DateKey.isToday(viewModel.selectedDate) ? "今天" : "未完成"
    }

    private var activeSectionEmptyText: String {
        DateKey.isToday(viewModel.selectedDate) ? "今天暂无任务" : "当天暂无未完成任务"
    }

    var body: some View {
        let key = viewModel.dateKey(for: viewModel.selectedDate)
        let progress = viewModel.progress(for: key)
        let sections = viewModel.sections(for: key)

        List {
            HStack {
                Text("日历")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(BigStartPalette.textPrimary)
                Spacer()
            }
            .bigStartListRow(top: 20, bottom: 8)

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
            .bigStartListRow(bottom: 12)

            BigStartCard(
                background: LinearGradient(
                    colors: [Color(red: 0.929, green: 0.961, blue: 1.0), Color(red: 0.969, green: 0.984, blue: 1.0)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                borderColor: BigStartPalette.accent.opacity(0.12)
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(DateKey.longTitle(for: viewModel.selectedDate))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(BigStartPalette.textPrimary)
                        Spacer()
                        CompactProgressPill(progress: progress)
                    }
                }
            }
            .bigStartListRow(bottom: 12)

            if sections.pinned.isEmpty && sections.active.isEmpty && sections.completed.isEmpty {
                BigStartCard {
                    EmptyStateView(title: "当天暂无任务", description: "切换日期或返回清单页添加任务。", systemImage: "calendar.badge.exclamationmark")
                }
                .bigStartListRow(bottom: 12)
            }

            CollapsibleTaskListSection(
                title: "置顶",
                count: sections.pinned.count,
                style: .pinned,
                emptyText: "当天暂无置顶任务",
                isExpanded: $pinnedExpanded,
                topSpacing: 4,
                items: sections.pinned
            ) { task in
                CalendarTaskRowView(task: task, dateKey: key, sectionStyle: .pinned)
            }

            CollapsibleTaskListSection(
                title: activeSectionTitle,
                count: sections.active.count,
                style: .active,
                emptyText: activeSectionEmptyText,
                isExpanded: $activeExpanded,
                topSpacing: 10,
                items: sections.active
            ) { task in
                CalendarTaskRowView(task: task, dateKey: key, sectionStyle: .active)
            }

            CollapsibleTaskListSection(
                title: "已完成",
                count: sections.completed.count,
                style: .completed,
                emptyText: "当天暂无已完成任务",
                isExpanded: $completedExpanded,
                topSpacing: 10,
                items: sections.completed
            ) { task in
                CalendarTaskRowView(task: task, dateKey: key, sectionStyle: .completed)
            }

            Color.clear
                .frame(height: 120)
                .bigStartListRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        .onAppear {
            visibleMonth = viewModel.selectedDate
            resetSectionStates()
        }
        .onChange(of: viewModel.selectedDate) { newDate in
            visibleMonth = newDate
            resetSectionStates()
        }
    }

    private func shiftMonth(by offset: Int) -> Date {
        DateKey.calendar.date(byAdding: .month, value: offset, to: visibleMonth) ?? visibleMonth
    }

    private func resetSectionStates() {
        pinnedExpanded = false
        activeExpanded = true
        completedExpanded = false
    }
}

struct MemoScreen: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private func memoRowID(_ id: String) -> String {
        "memo-\(id)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                VStack(alignment: .leading, spacing: 6) {
                    Text("备忘录")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(BigStartPalette.textPrimary)
                    Text("\(viewModel.memos.count) 条记录")
                        .font(.subheadline)
                        .foregroundStyle(BigStartPalette.textSecondary)
                }
                .bigStartListRow(top: 20, bottom: 10)

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
                .bigStartListRow(bottom: 12)

                if viewModel.memosSorted().isEmpty {
                    BigStartCard {
                        EmptyStateView(title: "暂无备忘录", description: "可以从任务右滑添加，也可以直接在这里新建。", systemImage: "note.text")
                    }
                    .bigStartListRow(bottom: 12)
                } else {
                    ForEach(viewModel.memosSorted()) { memo in
                        MemoRowView(memo: memo, highlighted: viewModel.highlightedMemoID == memo.id)
                            .id(memoRowID(memo.id))
                            .task {
                                if viewModel.highlightedMemoID == memo.id {
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    viewModel.clearHighlightIfNeeded(memoID: memo.id)
                                }
                            }
                            .bigStartListRow(bottom: 8)
                    }
                }

                Color.clear
                    .frame(height: 120)
                    .bigStartListRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onAppear {
                guard let id = viewModel.highlightedMemoID else { return }
                revealMemoResult(id: id, proxy: proxy)
            }
            .onChange(of: viewModel.highlightedMemoID) { id in
                guard let id else { return }
                revealMemoResult(id: id, proxy: proxy)
            }
        }
    }

    private func revealMemoResult(id: String, proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            withAnimation(.easeInOut(duration: 0.28)) {
                proxy.scrollTo(memoRowID(id), anchor: .center)
            }
        }
    }
}

struct AIAssistantScreen: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var recorder: AudioRecorderManager
    @EnvironmentObject private var transcriber: SpeechTranscriber
    @State private var showingInputSheet = false
    @State private var isPressingMainButton = false
    @State private var didTriggerLongPress = false
    @State private var longPressTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BigStartCard(
                    background: LinearGradient(
                        colors: [Color(red: 0.93, green: 0.97, blue: 1.0), Color.white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    borderColor: BigStartPalette.accent.opacity(0.14)
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("AI 助手")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(BigStartPalette.textPrimary)
                                Text("点击输入文字，长按开始录音。解析后会直接创建清单或备忘。")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(BigStartPalette.textSecondary)
                            }
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(BigStartPalette.accent.opacity(0.12))
                                    .frame(width: 54, height: 54)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(BigStartPalette.accent)
                            }
                        }

                        HStack(spacing: 8) {
                            Capsule()
                                .fill(viewModel.aiReady ? Color.green.opacity(0.16) : Color.orange.opacity(0.16))
                                .frame(width: 10, height: 10)
                                Text(viewModel.aiReady ? "AI 已配置" : "请先到“我的”页面配置 AI")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(viewModel.aiReady ? Color.green : Color.orange)
                        }
                    }
                }

                BigStartCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("最近结果")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(BigStartPalette.textPrimary)
                            Spacer()
                            if viewModel.aiRequestState.isLoading {
                                ProgressView()
                                    .scaleEffect(0.9)
                            }
                        }

                        Text(statusMessage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(statusColor)

                        if let result = viewModel.lastAIResult {
                            VStack(alignment: .leading, spacing: 10) {
                                resultBlock(title: "转写文本", value: result.transcript)
                                resultBlock(title: "识别类型", value: resultLabel(for: result.intent))
                                if let task = result.task {
                                    resultBlock(title: "清单", value: "\(task.text) · \(task.dateKey)")
                                }
                                if let memo = result.memo {
                                    let memoValue = [memo.title, memo.dateKey, memo.content]
                                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                        .joined(separator: " · ")
                                    resultBlock(title: "备忘", value: memoValue)
                                }
                            }
                        } else {
                            Text("完成一次 AI 输入后，这里会显示最近的解析与创建结果。")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(BigStartPalette.textSecondary)
                        }
                    }
                }

                BigStartCard(
                    background: LinearGradient(
                        colors: recorder.isRecording
                            ? [Color(red: 0.88, green: 0.95, blue: 1.0), Color.white]
                            : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    borderColor: recorder.isRecording ? BigStartPalette.accent.opacity(0.24) : Color.black.opacity(0.04)
                ) {
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: recorder.isRecording
                                            ? [Color(red: 0.15, green: 0.55, blue: 0.96), Color(red: 0.06, green: 0.39, blue: 0.86)]
                                            : [Color(red: 0.14, green: 0.47, blue: 0.95), Color(red: 0.29, green: 0.57, blue: 0.98)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 124, height: 124)
                                .shadow(color: BigStartPalette.accent.opacity(0.28), radius: 18, x: 0, y: 12)
                            Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "sparkles")
                                .font(.system(size: 38, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .contentShape(Circle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    handleMainButtonPressBegan()
                                }
                                .onEnded { _ in
                                    handleMainButtonPressEnded()
                                }
                        )

                        VStack(spacing: 8) {
                            Text(recorder.isRecording ? "松开发送语音" : "点击输入，长按说话")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(BigStartPalette.textPrimary)

                            Text(recorder.isRecording ? recorder.elapsedLabel : "支持自然语言时间解析，例如“周六下午和好友聚聚”。")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(BigStartPalette.textSecondary)
                                .multilineTextAlignment(.center)
                        }

                        if !viewModel.aiReady {
                            Button {
                                viewModel.setSelectedTab(.me)
                            } label: {
                                Text("前往配置 AI 服务")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(BigStartPalette.accent)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(BigStartPalette.accent.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .opacity(viewModel.aiReady ? 1 : 0.92)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 132)
        }
        .sheet(isPresented: $showingInputSheet) {
            AITextInputSheet()
                .environmentObject(viewModel)
        }
        .onChange(of: recorder.didReachMaxDuration) { reachedLimit in
            guard reachedLimit else { return }
            Task {
                await finishVoiceCapture()
            }
        }
        .onDisappear {
            longPressTask?.cancel()
            recorder.cancelRecording()
        }
    }

    private var statusMessage: String {
        viewModel.aiRequestState.message ?? "等待输入"
    }

    private var statusColor: Color {
        switch viewModel.aiRequestState {
        case .idle:
            return BigStartPalette.textSecondary
        case .loading:
            return BigStartPalette.accent
        case .success:
            return Color.green
        case .failure:
            return Color.orange
        }
    }

    @ViewBuilder
    private func resultBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BigStartPalette.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(BigStartPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func resultLabel(for intent: AIIntentKind) -> String {
        switch intent {
        case .task:
            return "清单"
        case .memo:
            return "备忘"
        case .taskWithMemo:
            return "清单 + 备注"
        case .unknown:
            return "未识别"
        }
    }

    private func handleMainButtonPressBegan() {
        guard !isPressingMainButton else { return }
        isPressingMainButton = true
        didTriggerLongPress = false

        longPressTask?.cancel()
        longPressTask = Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled, isPressingMainButton else { return }
            didTriggerLongPress = true

            guard viewModel.aiReady else {
                await MainActor.run {
                    viewModel.aiRequestState = .failure("请先在“我的”界面完成 AI 配置。")
                }
                return
            }

            do {
                let permissionState = try await recorder.startRecording()
                await MainActor.run {
                    viewModel.updateMicrophonePermission(permissionState)
                    if permissionState != .granted {
                        viewModel.aiRequestState = .failure("请先允许麦克风权限，再进行语音输入。")
                    }
                }
            } catch {
                await MainActor.run {
                    viewModel.aiRequestState = .failure(error.localizedDescription)
                }
            }
        }
    }

    private func handleMainButtonPressEnded() {
        isPressingMainButton = false
        longPressTask?.cancel()
        longPressTask = nil

        if recorder.isRecording || recorder.hasPendingRecording {
            Task {
                await finishVoiceCapture()
            }
        } else if !didTriggerLongPress {
            if viewModel.aiReady {
                showingInputSheet = true
            } else {
                viewModel.setSelectedTab(.me)
            }
        }

        didTriggerLongPress = false
    }

    private func finishVoiceCapture() async {
        do {
            let audioURL = try recorder.finishRecording()
            await viewModel.submitAIVoice(audioURL: audioURL, fallbackTranscriber: transcriber)
        } catch {
            if (error as? AudioRecorderManagerError) != .noRecording {
                viewModel.aiRequestState = .failure(error.localizedDescription)
            }
        }
    }
}

struct AITextInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var inputType: AIManualInputType = .task
    @State private var inputText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                BigStartBackground()
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    BigStartCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("类型", selection: $inputType) {
                                ForEach(AIManualInputType.allCases) { type in
                                    Text(type.title).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)

                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
                                    .frame(minHeight: 180)

                                if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(inputType == .task ? "例如：周六下午和好友聚聚" : "例如：明天提醒我看牙")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(BigStartPalette.textSecondary)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 16)
                                }

                                TextEditor(text: $inputText)
                                    .scrollContentBackground(.hidden)
                                    .padding(12)
                                    .frame(minHeight: 180)
                                    .foregroundStyle(BigStartPalette.textPrimary)
                                    .background(Color.clear)
                            }

                            Button {
                                Task {
                                    await viewModel.submitAIText(input: inputText, typeHint: inputType)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Spacer()
                                    Text(viewModel.aiRequestState.isLoading ? "处理中…" : "发送并创建")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                }
                                .padding(.vertical, 14)
                                .background(BigStartPalette.accentGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.aiReady || viewModel.aiRequestState.isLoading)
                            .opacity(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.aiReady ? 0.55 : 1)
                        }
                    }

                    if !viewModel.aiReady {
                        Text("请先到“我的”页面填写 DeepSeek API Key。")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.orange)
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("AI 输入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct MeSettingsScreen: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var baseURLText = ""
    @State private var accessToken = ""
    @State private var feedbackMessage = ""
    @State private var isTesting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BigStartCard(
                    background: LinearGradient(
                        colors: [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    borderColor: BigStartPalette.accent.opacity(0.12)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("我的")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(BigStartPalette.textPrimary)
                        Text("这里只需要填写 DeepSeek 官方地址和 API Key。长按语音会先在本机转成文字，再直接交给 DeepSeek 解析。")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(BigStartPalette.textSecondary)
                    }
                }

                BigStartCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("AI 服务设置")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(BigStartPalette.textPrimary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("DeepSeek API 地址")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(BigStartPalette.textSecondary)
                            TextField("https://api.deepseek.com", text: $baseURLText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .frame(height: 50)
                                .background(Color(red: 0.97, green: 0.98, blue: 1.0))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text("默认就是官方地址，一般不用修改。")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(BigStartPalette.textSecondary.opacity(0.8))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("DeepSeek API Key")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(BigStartPalette.textSecondary)
                            SecureField("sk-...", text: $accessToken)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .frame(height: 50)
                                .background(Color(red: 0.97, green: 0.98, blue: 1.0))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        HStack(spacing: 10) {
                            Button {
                                do {
                                    try viewModel.saveAISettings(baseURLString: baseURLText, accessToken: accessToken)
                                    feedbackMessage = "AI 配置已保存。"
                                } catch {
                                    feedbackMessage = error.localizedDescription
                                }
                            } label: {
                                Text("保存")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(BigStartPalette.accentGradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task {
                                    isTesting = true
                                    defer { isTesting = false }
                                    do {
                                        feedbackMessage = try await viewModel.testAIConnection(baseURLString: baseURLText, accessToken: accessToken)
                                    } catch {
                                        feedbackMessage = error.localizedDescription
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if isTesting {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                    Text(isTesting ? "测试中" : "测试连接")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundStyle(BigStartPalette.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(BigStartPalette.accent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(isTesting)
                        }

                        if !feedbackMessage.isEmpty {
                            Text(feedbackMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(feedbackMessage.contains("成功") ? Color.green : Color.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 132)
        }
        .onAppear {
            baseURLText = viewModel.aiSettings.baseURL.absoluteString
            accessToken = viewModel.aiSettings.accessToken
        }
    }
}

enum SpeechTranscriberError: LocalizedError {
    case recognizerUnavailable
    case permissionDenied
    case noTranscription

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "语音识别暂时不可用。"
        case .permissionDenied:
            return "请先允许语音识别权限。"
        case .noTranscription:
            return "没有识别到有效语音内容。"
        }
    }
}

@MainActor
final class SpeechTranscriber: ObservableObject {
    func transcribeLocally(audioURL: URL) async throws -> String {
        let authorization = await requestAuthorization()
        guard authorization == .authorized else {
            throw SpeechTranscriberError.permissionDenied
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN")) ?? SFSpeechRecognizer(),
              recognizer.isAvailable
        else {
            throw SpeechTranscriberError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            var recognitionTask: SFSpeechRecognitionTask?

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if didResume { return }

                if let error {
                    didResume = true
                    recognitionTask?.cancel()
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal else { return }
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                didResume = true
                recognitionTask?.cancel()
                if text.isEmpty {
                    continuation.resume(throwing: SpeechTranscriberError.noTranscription)
                } else {
                    continuation.resume(returning: text)
                }
            }
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        try await transcribeLocally(audioURL: audioURL)
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined {
            return current
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

enum AudioRecorderManagerError: LocalizedError, Equatable {
    case noRecording
    case denied
    case unableToStart

    var errorDescription: String? {
        switch self {
        case .noRecording:
            return "没有可提交的录音。"
        case .denied:
            return "请先允许麦克风权限。"
        case .unableToStart:
            return "录音启动失败。"
        }
    }
}

@MainActor
final class AudioRecorderManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var didReachMaxDuration = false

    var hasPendingRecording: Bool {
        recordingURL != nil && !isRecording
    }

    var elapsedLabel: String {
        let totalSeconds = Int(elapsed)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "录音中 %02d:%02d", minutes, seconds)
    }

    private let maxDuration: TimeInterval = 60
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var timer: Timer?

    func startRecording() async throws -> MicrophonePermissionState {
        let permission = await requestPermission()
        guard permission == .granted else {
            return permission
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            throw AudioRecorderManagerError.unableToStart
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ai-voice-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            guard recorder.record() else {
                throw AudioRecorderManagerError.unableToStart
            }

            self.recorder = recorder
            recordingURL = url
            elapsed = 0
            didReachMaxDuration = false
            isRecording = true
            startTimer()
        } catch {
            throw AudioRecorderManagerError.unableToStart
        }

        return .granted
    }

    func finishRecording() throws -> URL {
        if isRecording {
            stopRecording(keepFile: true, reachedLimit: false)
        }

        guard let url = recordingURL else {
            throw AudioRecorderManagerError.noRecording
        }

        recordingURL = nil
        didReachMaxDuration = false
        return url
    }

    func cancelRecording() {
        stopRecording(keepFile: false, reachedLimit: false)
    }

    private func requestPermission() async -> MicrophonePermissionState {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            return granted ? .granted : .denied
        @unknown default:
            return .denied
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.elapsed += 0.2
                if self.elapsed >= self.maxDuration {
                    self.stopRecording(keepFile: true, reachedLimit: true)
                }
            }
        }
    }

    private func stopRecording(keepFile: Bool, reachedLimit: Bool) {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        didReachMaxDuration = reachedLimit
        elapsed = min(elapsed, maxDuration)

        if !keepFile, let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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

    var accent: Color {
        switch self {
        case .pinned: return .orange
        case .active: return BigStartPalette.accent
        case .completed: return .green
        }
    }

    var symbol: String {
        switch self {
        case .pinned: return "pin.fill"
        case .active: return "sun.max.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

private struct BigStartListRowModifier: ViewModifier {
    let top: CGFloat
    let bottom: CGFloat
    let horizontal: CGFloat

    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal))
    }
}

private extension View {
    func bigStartListRow(top: CGFloat = 0, bottom: CGFloat = 0, horizontal: CGFloat = 20) -> some View {
        modifier(BigStartListRowModifier(top: top, bottom: bottom, horizontal: horizontal))
    }
}

struct TaskSectionHeaderRow: View {
    let title: String
    let count: Int
    let style: BigStartSectionStyle
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(style.accent.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: style.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(style.accent)
                }

                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(BigStartPalette.textPrimary)
                Spacer()

                Text("\(count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(style.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(style.accent.opacity(0.12))
                    )

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BigStartPalette.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(style.accent.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: style.accent.opacity(0.08), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

struct TaskSectionEmptyRow: View {
    let text: String
    let style: BigStartSectionStyle

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(BigStartPalette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(style.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(style.borderColor, lineWidth: 1)
            )
    }
}

struct CollapsibleTaskListSection<Item: Identifiable, RowContent: View>: View {
    let title: String
    let count: Int
    let style: BigStartSectionStyle
    let emptyText: String
    @Binding var isExpanded: Bool
    let topSpacing: CGFloat
    let items: [Item]
    @ViewBuilder let rowContent: (Item) -> RowContent

    var body: some View {
        Group {
            if !items.isEmpty {
                TaskSectionHeaderRow(
                    title: title,
                    count: count,
                    style: style,
                    isExpanded: isExpanded
                ) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                }
                .bigStartListRow(top: topSpacing, bottom: isExpanded ? 6 : 10)

                if isExpanded {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        rowContent(item)
                            .bigStartListRow(bottom: index == items.count - 1 ? 12 : 8, horizontal: 28)
                    }
                }
            }
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
                            TaskRowView(
                                task: task,
                                dateKey: dateKey,
                                highlighted: viewModel.highlightedTaskID == task.id,
                                sectionStyle: style
                            )
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

struct TaskRowView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let task: TaskItem
    let dateKey: String
    let highlighted: Bool
    let sectionStyle: BigStartSectionStyle

    var body: some View {
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
        .contentShape(Rectangle())
        .onTapGesture {
            if !task.done {
                viewModel.openTaskEditor(task: task, dateKey: dateKey)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                viewModel.openMemoEditorForTask(task: task, dateKey: dateKey)
            } label: {
                Label("备忘", systemImage: "note.text.badge.plus")
            }
            .tint(.blue)

            Button {
                viewModel.togglePin(task: task, dateKey: dateKey)
            } label: {
                Label("置顶", systemImage: "pin.fill")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                viewModel.openMoveEditor(task: task, dateKey: dateKey)
            } label: {
                Label("改期", systemImage: "calendar")
            }
            .tint(.green)

            Button(role: .destructive) {
                viewModel.deleteTask(task: task, dateKey: dateKey)
            } label: {
                Label("删除", systemImage: "trash.fill")
            }
        }
    }
}

struct CalendarTaskRowView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let task: TaskItem
    let dateKey: String
    let sectionStyle: BigStartSectionStyle

    var body: some View {
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
        .contentShape(Rectangle())
        .onTapGesture {
            if !task.done {
                viewModel.openTaskEditor(task: task, dateKey: dateKey)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                viewModel.openMemoEditorForTask(task: task, dateKey: dateKey)
            } label: {
                Label("备忘", systemImage: "note.text.badge.plus")
            }
            .tint(.blue)

            Button {
                viewModel.togglePin(task: task, dateKey: dateKey)
            } label: {
                Label("置顶", systemImage: "pin.fill")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                viewModel.openMoveEditor(task: task, dateKey: dateKey)
            } label: {
                Label("改期", systemImage: "calendar")
            }
            .tint(.green)

            Button(role: .destructive) {
                viewModel.deleteTask(task: task, dateKey: dateKey)
            } label: {
                Label("删除", systemImage: "trash.fill")
            }
        }
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
        BigStartCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(DateKey.shortDateLabel(for: DateKey.date(from: memo.date)))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BigStartPalette.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(BigStartPalette.accent.opacity(0.10))
                        )

                    Text(memo.taskTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BigStartPalette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }

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
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.openMemoEditor(memo)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                viewModel.deleteMemo(memo)
            } label: {
                Label("删除", systemImage: "trash.fill")
            }
        }
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
                    let undoneCount = max(0, dayProgress.total - dayProgress.done)
                    let hasMemoMark = hasMemo(key)
                    Button {
                        onSelect(date)
                    } label: {
                        ZStack {
                            Text("\(DateKey.calendar.component(.day, from: date))")
                                .font(.subheadline.weight(isSelected ? .bold : .regular))
                                .zIndex(1)

                            CalendarDayMarks(
                                doneCount: dayProgress.done,
                                undoneCount: undoneCount,
                                hasMemo: hasMemoMark,
                                isSelected: isSelected
                            )
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

private struct CalendarDayMarks: View {
    let doneCount: Int
    let undoneCount: Int
    let hasMemo: Bool
    let isSelected: Bool

    var body: some View {
        ZStack {
            if doneCount > 0 {
                CalendarCountBadge(
                    text: "\(doneCount)",
                    background: Color(red: 0.204, green: 0.780, blue: 0.349),
                    alignment: .topTrailing
                )
            }

            if undoneCount > 0 {
                CalendarCountBadge(
                    text: "\(undoneCount)",
                    background: Color(red: 1.0, green: 0.231, blue: 0.188),
                    alignment: .topLeading
                )
            }

            if hasMemo {
                CalendarMemoDot(isSelected: isSelected)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

private struct CalendarCountBadge: View {
    let text: String
    let background: Color
    let alignment: Alignment

    var body: some View {
        VStack {
            HStack {
                if alignment == .topTrailing {
                    Spacer(minLength: 0)
                }

                Text(text)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: badgeWidth, height: 14)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(background)
                    )

                if alignment == .topLeading {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
    }

    private var badgeWidth: CGFloat {
        max(14, CGFloat(text.count) * 6 + 8)
    }
}

private struct CalendarMemoDot: View {
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: isSelected
                        ? [Color(red: 1.0, green: 0.941, blue: 0.659), Color(red: 1.0, green: 0.882, blue: 0.506)]
                        : [Color(red: 0.969, green: 0.843, blue: 0.408), Color(red: 0.957, green: 0.784, blue: 0.290), Color(red: 0.914, green: 0.714, blue: 0.184)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 8, height: 8)
            .shadow(color: isSelected ? BigStartPalette.accent.opacity(0.18) : Color(red: 0.914, green: 0.714, blue: 0.184).opacity(0.2), radius: isSelected ? 6 : 5, x: 0, y: 2)
            .overlay(
                Circle()
                    .stroke(isSelected ? BigStartPalette.accent.opacity(0.18) : Color.white.opacity(0.98), lineWidth: 2)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 4)
    }
}

private struct TaskInputDatePickerDay: Identifiable {
    let id: String
    let date: Date
    let isCurrentMonth: Bool
    let isPast: Bool
}

struct TaskInputDatePickerPanel: View {
    @Binding var visibleMonth: Date
    let selectedDate: Date
    let minimumDate: Date
    let onSelect: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    visibleMonth = shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BigStartPalette.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(DateKey.monthTitle(for: visibleMonth))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BigStartPalette.textPrimary)

                Spacer()

                Button {
                    visibleMonth = shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BigStartPalette.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BigStartPalette.textSecondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(dayEntries()) { entry in
                    let isSelected = DateKey.isSameDay(entry.date, selectedDate)
                    let isToday = DateKey.isToday(entry.date)
                    let isEnabled = !entry.isPast

                    Button {
                        guard isEnabled else { return }
                        if !entry.isCurrentMonth {
                            visibleMonth = entry.date
                        }
                        onSelect(entry.date)
                    } label: {
                        Text("\(DateKey.calendar.component(.day, from: entry.date))")
                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(dayTextColor(entry: entry, isSelected: isSelected))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                Circle()
                                    .fill(isSelected ? BigStartPalette.accent : Color.clear)
                            )
                            .overlay(
                                Circle()
                                    .stroke(isToday && !isSelected ? BigStartPalette.accent : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BigStartPalette.accent.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 10)
    }

    private func shiftMonth(by value: Int) -> Date {
        DateKey.calendar.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
    }

    private func dayEntries() -> [TaskInputDatePickerDay] {
        let startOfMonth = DateKey.calendar.date(
            from: DateKey.calendar.dateComponents([.year, .month], from: visibleMonth)
        ) ?? visibleMonth
        let today = DateKey.normalized(minimumDate)
        let daysInMonth = DateKey.calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30
        let firstWeekday = DateKey.calendar.component(.weekday, from: startOfMonth)

        let previousMonth = DateKey.calendar.date(byAdding: .month, value: -1, to: startOfMonth) ?? startOfMonth
        let previousMonthCount = DateKey.calendar.range(of: .day, in: .month, for: previousMonth)?.count ?? 30

        var values: [TaskInputDatePickerDay] = []

        if firstWeekday > 1 {
            for day in (previousMonthCount - firstWeekday + 2)...previousMonthCount {
                if let date = DateKey.calendar.date(byAdding: .day, value: day - 1, to: previousMonth) {
                    let normalizedDate = DateKey.normalized(date)
                    values.append(TaskInputDatePickerDay(
                        id: "prev-\(DateKey.string(from: normalizedDate))",
                        date: normalizedDate,
                        isCurrentMonth: false,
                        isPast: normalizedDate < today
                    ))
                }
            }
        }

        for day in 1...daysInMonth {
            if let date = DateKey.calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                let normalizedDate = DateKey.normalized(date)
                values.append(TaskInputDatePickerDay(
                    id: DateKey.string(from: normalizedDate),
                    date: normalizedDate,
                    isCurrentMonth: true,
                    isPast: normalizedDate < today
                ))
            }
        }

        let remaining = max(0, 42 - values.count)
        let nextMonth = DateKey.calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? startOfMonth
        for day in 1...remaining {
            if let date = DateKey.calendar.date(byAdding: .day, value: day - 1, to: nextMonth) {
                let normalizedDate = DateKey.normalized(date)
                values.append(TaskInputDatePickerDay(
                    id: "next-\(DateKey.string(from: normalizedDate))",
                    date: normalizedDate,
                    isCurrentMonth: false,
                    isPast: normalizedDate < today
                ))
            }
        }

        return values
    }

    private func dayTextColor(entry: TaskInputDatePickerDay, isSelected: Bool) -> Color {
        if isSelected {
            return .white
        }
        if entry.isPast {
            return Color(red: 0.78, green: 0.78, blue: 0.80)
        }
        if !entry.isCurrentMonth {
            return BigStartPalette.textSecondary
        }
        return BigStartPalette.textPrimary
    }
}

struct SearchSheetView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let queryEmpty = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let results = viewModel.searchResults()
        let taskResults = results.filter { $0.kind == .task }
        let memoResults = results.filter { $0.kind == .memo }

        NavigationStack {
            List {
                if queryEmpty {
                    EmptyStateView(title: "搜索", description: "输入关键词搜索清单和备忘录。", systemImage: "magnifyingglass")
                } else if results.isEmpty {
                    EmptyStateView(title: "未找到相关内容", description: "换个关键词试试。", systemImage: "magnifyingglass")
                } else {
                    Section {
                        Text("找到 \(results.count) 条结果")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(BigStartPalette.textSecondary)
                    }
                    if !taskResults.isEmpty {
                        Section("清单 \(taskResults.count)") {
                            ForEach(taskResults) { result in
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
                    if !memoResults.isEmpty {
                        Section("备忘录 \(memoResults.count)") {
                            ForEach(memoResults) { result in
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
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
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
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(result.kind == .task ? BigStartPalette.accent.opacity(0.12) : Color.orange.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: result.kind == .task ? "checklist" : "note.text")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(result.kind == .task ? BigStartPalette.accent : Color.orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(result.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BigStartPalette.textPrimary)
                    .lineLimit(2)
                Text(result.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BigStartPalette.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BigStartPalette.textSecondary.opacity(0.7))
        }
        .padding(.vertical, 6)
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
        rowContent
            .overlay {
                HorizontalSwipeGestureInstaller(
                    isClosed: settledOffset == 0,
                    allowsPositiveDirection: leadingWidth > 0,
                    allowsNegativeDirection: trailingWidth > 0,
                    onStart: beginHorizontalDrag,
                    onChanged: updateHorizontalDrag,
                    onEnd: endHorizontalDrag
                )
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if actionsAreOpen {
                    closeActions()
                }
            }
            .animation(settleAnimation, value: settledOffset)
            .onChange(of: viewModel.openSwipeID) { openID in
                if openID != swipeID && settledOffset != 0 {
                    closeActions()
                }
            }
            .onDisappear {
                if viewModel.openSwipeID == swipeID {
                    viewModel.setOpenSwipe(id: nil)
                }
            }
    }

    private var rowContent: some View {
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
    }

    private func beginHorizontalDrag() {
        guard !isDraggingHorizontally else { return }
        isDraggingHorizontally = true
        dragBaseOffset = settledOffset
        dragTranslation = 0
        if viewModel.openSwipeID != nil && viewModel.openSwipeID != swipeID {
            viewModel.setOpenSwipe(id: nil)
        }
    }

    private func updateHorizontalDrag(_ translationX: CGFloat) {
        if !isDraggingHorizontally {
            beginHorizontalDrag()
        }
        dragTranslation = translationX
    }

    private func endHorizontalDrag(_ translationX: CGFloat, velocityX: CGFloat, cancelled: Bool) {
        guard isDraggingHorizontally else { return }

        let actual = min(max(dragBaseOffset + translationX, -trailingWidth), leadingWidth)
        let projected = dragBaseOffset + translationX + (cancelled ? 0 : velocityProjection(for: velocityX))
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

        if openSwipeID == swipeID {
            viewModel.setOpenSwipe(id: swipeID)
        } else if viewModel.openSwipeID == swipeID {
            viewModel.setOpenSwipe(id: nil)
        }
    }

    private func velocityProjection(for velocityX: CGFloat) -> CGFloat {
        velocityX * 0.12
    }

    private func closeActions() {
        withAnimation(settleAnimation) {
            settledOffset = 0
            dragTranslation = 0
            isDraggingHorizontally = false
        }
        dragBaseOffset = 0
        if viewModel.openSwipeID == swipeID {
            viewModel.setOpenSwipe(id: nil)
        }
    }
}

private struct HorizontalSwipeGestureInstaller: UIViewRepresentable {
    let isClosed: Bool
    let allowsPositiveDirection: Bool
    let allowsNegativeDirection: Bool
    let onStart: () -> Void
    let onChanged: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onStart: onStart,
            onChanged: onChanged,
            onEnd: onEnd
        )
    }

    func makeUIView(context: Context) -> GestureInstallerView {
        let view = GestureInstallerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onHostViewChange = { installerView in
            context.coordinator.install(from: installerView)
        }
        return view
    }

    func updateUIView(_ uiView: GestureInstallerView, context: Context) {
        context.coordinator.isClosed = isClosed
        context.coordinator.allowsPositiveDirection = allowsPositiveDirection
        context.coordinator.allowsNegativeDirection = allowsNegativeDirection
        context.coordinator.onStart = onStart
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnd = onEnd
        uiView.onHostViewChange = { installerView in
            context.coordinator.install(from: installerView)
        }
        DispatchQueue.main.async {
            uiView.onHostViewChange?(uiView)
        }
    }

    static func dismantleUIView(_ uiView: GestureInstallerView, coordinator: Coordinator) {
        coordinator.install(from: nil)
    }

    final class Coordinator: NSObject {
        var isClosed = true
        var allowsPositiveDirection = false
        var allowsNegativeDirection = false
        var onStart: () -> Void
        var onChanged: (CGFloat) -> Void
        var onEnd: (CGFloat, CGFloat, Bool) -> Void
        private let recognizer: AxisLockedHorizontalPanRecognizer
        private weak var gestureHostView: UIView?
        private weak var scrollView: UIScrollView?

        init(
            onStart: @escaping () -> Void,
            onChanged: @escaping (CGFloat) -> Void,
            onEnd: @escaping (CGFloat, CGFloat, Bool) -> Void
        ) {
            self.onStart = onStart
            self.onChanged = onChanged
            self.onEnd = onEnd
            self.recognizer = AxisLockedHorizontalPanRecognizer()
            super.init()
            recognizer.addTarget(self, action: #selector(handlePan(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
        }

        func install(from installerView: UIView?) {
            let hostView = findGestureHost(from: installerView)

            if let currentHost = self.gestureHostView, recognizer.view === currentHost, currentHost !== hostView {
                currentHost.removeGestureRecognizer(recognizer)
            }

            self.gestureHostView = hostView

            guard let hostView else {
                scrollView = nil
                return
            }

            if recognizer.view !== hostView {
                hostView.addGestureRecognizer(recognizer)
            }

            recognizer.isClosed = isClosed
            recognizer.allowsPositiveDirection = allowsPositiveDirection
            recognizer.allowsNegativeDirection = allowsNegativeDirection

            let nearestScrollView = findNearestScrollView(from: hostView)
            if scrollView !== nearestScrollView {
                scrollView = nearestScrollView
            }
            nearestScrollView?.panGestureRecognizer.require(toFail: recognizer)
        }

        @objc private func handlePan(_ recognizer: AxisLockedHorizontalPanRecognizer) {
            recognizer.isClosed = isClosed
            recognizer.allowsPositiveDirection = allowsPositiveDirection
            recognizer.allowsNegativeDirection = allowsNegativeDirection

            switch recognizer.state {
            case .began:
                onStart()
                onChanged(recognizer.translationX)
            case .changed:
                onChanged(recognizer.translationX)
            case .ended:
                onEnd(recognizer.translationX, recognizer.velocityX, false)
            case .cancelled, .failed:
                onEnd(recognizer.translationX, recognizer.velocityX, true)
            default:
                break
            }
        }

        private func findNearestScrollView(from view: UIView?) -> UIScrollView? {
            var current = view?.superview
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView {
                    return scrollView
                }
                current = candidate.superview
            }
            return nil
        }

        private func findGestureHost(from installerView: UIView?) -> UIView? {
            guard var subtreeRoot = installerView else { return nil }

            while let parent = subtreeRoot.superview {
                let hasSiblingOutsideInstallerSubtree = parent.subviews.contains { sibling in
                    sibling !== subtreeRoot
                }
                if hasSiblingOutsideInstallerSubtree {
                    return parent
                }
                subtreeRoot = parent
            }

            return installerView?.superview
        }
    }

    final class AxisLockedHorizontalPanRecognizer: UIGestureRecognizer {
        enum LockedAxis {
            case undecided
            case horizontal
            case vertical
        }

        var isClosed = true
        var allowsPositiveDirection = false
        var allowsNegativeDirection = false
        private(set) var translationX: CGFloat = 0
        private(set) var velocityX: CGFloat = 0

        private var activeTouch: UITouch?
        private var initialPoint: CGPoint = .zero
        private var lastPoint: CGPoint = .zero
        private var lastTimestamp: TimeInterval = 0
        private var lockedAxis: LockedAxis = .undecided

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard state == .possible else {
                super.touchesBegan(touches, with: event)
                return
            }

            guard activeTouch == nil, let touch = touches.first, (event.allTouches?.count ?? 0) == 1, let view else {
                state = .failed
                return
            }

            activeTouch = touch
            initialPoint = touch.location(in: view)
            lastPoint = initialPoint
            lastTimestamp = touch.timestamp
            translationX = 0
            velocityX = 0
            lockedAxis = .undecided
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch = activeTouch, touches.contains(touch), let view else {
                super.touchesMoved(touches, with: event)
                return
            }

            let point = touch.location(in: view)
            let dx = point.x - initialPoint.x
            let dy = point.y - initialPoint.y

            if lockedAxis == .undecided {
                if hypot(dx, dy) < 4 {
                    updateTracking(point: point, timestamp: touch.timestamp, translation: dx)
                    return
                }

                if isClosed {
                    if dx > 0 && !allowsPositiveDirection {
                        translationX = dx
                        velocityX = 0
                        state = .failed
                        return
                    }
                    if dx < 0 && !allowsNegativeDirection {
                        translationX = dx
                        velocityX = 0
                        state = .failed
                        return
                    }
                }

                if abs(dy) >= 4 && abs(dy) > abs(dx) + 2 {
                    lockedAxis = .vertical
                    translationX = dx
                    velocityX = 0
                    state = .failed
                    return
                }

                if abs(dx) >= 6 && abs(dx) > abs(dy) + 2 {
                    lockedAxis = .horizontal
                    updateTracking(point: point, timestamp: touch.timestamp, translation: dx)
                    state = .began
                    return
                }

                updateTracking(point: point, timestamp: touch.timestamp, translation: dx)
                return
            }

            guard lockedAxis == .horizontal else {
                state = .failed
                return
            }

            updateTracking(point: point, timestamp: touch.timestamp, translation: dx)
            state = .changed
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch = activeTouch, touches.contains(touch), let view else {
                super.touchesEnded(touches, with: event)
                return
            }

            let point = touch.location(in: view)
            let dx = point.x - initialPoint.x
            updateTracking(point: point, timestamp: touch.timestamp, translation: dx)

            if lockedAxis == .horizontal, state == .began || state == .changed {
                state = .ended
            } else {
                state = .failed
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            if lockedAxis == .horizontal, state == .began || state == .changed {
                state = .cancelled
            } else {
                state = .failed
            }
        }

        override func reset() {
            super.reset()
            activeTouch = nil
            initialPoint = .zero
            lastPoint = .zero
            lastTimestamp = 0
            translationX = 0
            velocityX = 0
            lockedAxis = .undecided
        }

        private func updateTracking(point: CGPoint, timestamp: TimeInterval, translation: CGFloat) {
            translationX = translation
            let deltaTime = max(timestamp - lastTimestamp, 0.0001)
            velocityX = (point.x - lastPoint.x) / deltaTime
            lastPoint = point
            lastTimestamp = timestamp
        }
    }

    final class GestureInstallerView: UIView {
        var onHostViewChange: ((UIView?) -> Void)?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            onHostViewChange?(superview)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onHostViewChange?(superview)
        }
    }
}

struct CompactProgressPill: View {
    let progress: (done: Int, total: Int, percent: Double)

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 0.898, green: 0.898, blue: 0.918)).frame(width: 60, height: 6)
                Capsule().fill(BigStartPalette.accentGradient).frame(width: max(0, 60 * progress.percent), height: 6)
            }
            Text("\(progress.done)/\(progress.total)")
                .font(.system(size: 13, weight: .medium))
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
    @State private var visibleMonth: Date
    let draft: TaskMoveDraft

    private var minimumMoveDate: Date {
        let today = DateKey.normalized(Date())
        let original = DateKey.date(from: draft.fromDateKey)
        return min(today, original)
    }

    init(draft: TaskMoveDraft) {
        self.draft = draft
        let initialDate = DateKey.date(from: draft.fromDateKey)
        _date = State(initialValue: initialDate)
        _visibleMonth = State(
            initialValue: DateKey.calendar.date(
                from: DateKey.calendar.dateComponents([.year, .month], from: initialDate)
            ) ?? initialDate
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TaskInputDatePickerPanel(
                    visibleMonth: $visibleMonth,
                    selectedDate: date,
                    minimumDate: minimumMoveDate
                ) { pickedDate in
                    date = DateKey.normalized(pickedDate)
                }
                Spacer(minLength: 0)
            }
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

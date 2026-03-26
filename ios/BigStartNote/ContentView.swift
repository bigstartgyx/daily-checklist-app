import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var recorder = AudioRecorderManager()
    @StateObject private var transcriber = SpeechTranscriber()

    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BigStartBackground()
                    .ignoresSafeArea()

                Group {
                    switch viewModel.selectedTab {
                    case .list:
                        ChecklistScreen()
                    case .calendar:
                        CalendarScreen()
                    case .memo:
                        MemoScreen()
                    case .ai:
                        AIAssistantScreen()
                            .environmentObject(recorder)
                            .environmentObject(transcriber)
                    case .me:
                        MeSettingsScreen()
                    }
                }
                .environmentObject(viewModel)
                .padding(.bottom, contentBottomInsets(for: proxy))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BigStartBottomNav(selectedTab: $viewModel.selectedTab)
                    .environmentObject(viewModel)
                    .environmentObject(recorder)
                    .environmentObject(transcriber)
                    .padding(.horizontal, 12)
                    .padding(.bottom, bottomNavInset(for: proxy))
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    let screenHeight = UIScreen.main.bounds.height
                    let newHeight = max(0, screenHeight - frame.minY)
                    if newHeight != keyboardHeight {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            keyboardHeight = newHeight
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                if keyboardHeight != 0 {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        keyboardHeight = 0
                    }
                }
            }
        }
        .task {
            await viewModel.bootstrap()
        }
        .onChange(of: viewModel.selectedDate) { _ in
            viewModel.persistPreferences()
        }
        .onChange(of: viewModel.selectedTab) { _ in
            viewModel.persistPreferences()
        }
        .sheet(isPresented: $viewModel.showingSearch) {
            SearchSheetView()
                .environmentObject(viewModel)
        }
        .sheet(item: $viewModel.taskDraft) { draft in
            TaskEditorSheet(draft: draft)
                .environmentObject(viewModel)
        }
        .sheet(item: $viewModel.memoDraft) { draft in
            MemoEditorSheet(draft: draft)
                .environmentObject(viewModel)
        }
        .sheet(item: $viewModel.moveDraft) { draft in
            MoveTaskSheet(draft: draft)
                .environmentObject(viewModel)
        }
        .alert(
            "同步提示",
            isPresented: Binding(
                get: { viewModel.syncMessage != nil },
                set: { if !$0 { viewModel.syncMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {
                viewModel.syncMessage = nil
            }
        } message: {
            Text(viewModel.syncMessage ?? "")
        }
        .overlay {
            if viewModel.isLoading {
                ZStack {
                    Color.black.opacity(0.16).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.1)
                        Text("正在加载数据…")
                            .font(.headline)
                    }
                    .padding(26)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Group {
                if viewModel.isSyncing {
                    Label("同步中", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: viewModel.isSyncing)
        }
    }

    private func contentBottomInsets(for proxy: GeometryProxy) -> CGFloat {
        max(proxy.safeAreaInsets.bottom, 4)
    }

    private func bottomNavInset(for proxy: GeometryProxy) -> CGFloat {
        navKeyboardInset(for: proxy)
    }

    private func navKeyboardInset(for proxy: GeometryProxy) -> CGFloat {
        max(0, keyboardHeight - proxy.safeAreaInsets.bottom)
    }
}

struct BigStartBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.98, blue: 0.99),
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color(red: 0.97, green: 0.98, blue: 0.99)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.blue.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 10)
                .offset(x: 80, y: -50)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 180, height: 180)
                .blur(radius: 6)
                .offset(x: -50, y: 60)
        }
    }
}

struct BigStartBottomNav: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var recorder: AudioRecorderManager
    @EnvironmentObject private var transcriber: SpeechTranscriber
    @Binding var selectedTab: AppTab
    @State private var isPressingAIButton = false
    @State private var didTriggerLongPress = false
    @State private var longPressTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                NavItem(tab: .list, selectedTab: $selectedTab, label: "清单", systemImage: "checklist")
                NavItem(tab: .calendar, selectedTab: $selectedTab, label: "日历", systemImage: "calendar")
                Spacer(minLength: 48)
                NavItem(tab: .memo, selectedTab: $selectedTab, label: "备忘", systemImage: "note.text")
                NavItem(tab: .me, selectedTab: $selectedTab, label: "我的", systemImage: "person")
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: -3)

            VStack(spacing: 5) {
                Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(
                        LinearGradient(
                            colors: recorder.isRecording
                                ? [
                                    Color(red: 0.15, green: 0.55, blue: 0.96),
                                    Color(red: 0.06, green: 0.39, blue: 0.86)
                                ]
                                : [
                                    Color(red: 0.10, green: 0.45, blue: 0.91),
                                    Color(red: 0.26, green: 0.52, blue: 0.96)
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                    .shadow(color: Color.blue.opacity(0.35), radius: 22, x: 0, y: 10)
                Text("AI 助手")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.10, green: 0.45, blue: 0.91))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        handleAIButtonPressBegan()
                    }
                    .onEnded { _ in
                        handleAIButtonPressEnded()
                    }
            )
            .onChange(of: recorder.didReachMaxDuration) { reachedLimit in
                guard reachedLimit else { return }
                Task {
                    await finishVoiceCapture()
                }
            }
            .onDisappear {
                longPressTask?.cancel()
            }
            .offset(y: -14)
        }
    }

    private func handleAIButtonPressBegan() {
        guard !isPressingAIButton else { return }
        isPressingAIButton = true
        didTriggerLongPress = false

        longPressTask?.cancel()
        longPressTask = Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled, isPressingAIButton else { return }
            didTriggerLongPress = true
            selectedTab = .ai

            guard viewModel.aiReady else {
                viewModel.aiRequestState = .failure("请先在“我的”界面完成 AI 配置。")
                return
            }

            do {
                let permissionState = try await recorder.startRecording()
                viewModel.updateMicrophonePermission(permissionState)
                if permissionState != .granted {
                    viewModel.aiRequestState = .failure("请先允许麦克风权限，再进行语音输入。")
                }
            } catch {
                viewModel.aiRequestState = .failure(error.localizedDescription)
            }
        }
    }

    private func handleAIButtonPressEnded() {
        isPressingAIButton = false
        longPressTask?.cancel()
        longPressTask = nil

        if recorder.isRecording || recorder.hasPendingRecording {
            Task {
                await finishVoiceCapture()
            }
        } else if !didTriggerLongPress {
            selectedTab = .ai
        }

        didTriggerLongPress = false
    }

    private func finishVoiceCapture() async {
        do {
            selectedTab = .ai
            let audioURL = try recorder.finishRecording()
            await viewModel.submitAIVoice(audioURL: audioURL, fallbackTranscriber: transcriber)
        } catch {
            if (error as? AudioRecorderManagerError) != .noRecording {
                viewModel.aiRequestState = .failure(error.localizedDescription)
            }
        }
    }
}

struct NavItem: View {
    let tab: AppTab
    @Binding var selectedTab: AppTab
    let label: String
    let systemImage: String

    var isSelected: Bool { selectedTab == tab }

    var body: some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? Color.blue.opacity(0.12) : .clear)
                        .frame(width: 38, height: 28)
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 10, weight: .regular))
            }
            .foregroundStyle(isSelected ? Color(red: 0.10, green: 0.45, blue: 0.91) : Color.gray)
            .frame(width: 58)
        }
        .buttonStyle(.plain)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

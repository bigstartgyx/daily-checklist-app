import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
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
                    PlaceholderScreen(title: "AI 助手", description: "AI 助手功能敬请期待", systemImage: "sparkles")
                case .me:
                    PlaceholderScreen(title: "我的", description: "个人中心功能敬请期待", systemImage: "person.circle")
                }
            }
            .environmentObject(viewModel)

            BigStartBottomNav(selectedTab: $viewModel.selectedTab)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
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
            if viewModel.isSyncing {
                Label("同步中", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 12)
                    .padding(.trailing, 16)
            }
        }
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
    @Binding var selectedTab: AppTab

    var body: some View {
        ZStack {
            HStack {
                NavItem(tab: .list, selectedTab: $selectedTab, label: "清单", systemImage: "checklist")
                NavItem(tab: .calendar, selectedTab: $selectedTab, label: "日历", systemImage: "calendar")
                Spacer(minLength: 64)
                NavItem(tab: .memo, selectedTab: $selectedTab, label: "备忘", systemImage: "note.text")
                NavItem(tab: .me, selectedTab: $selectedTab, label: "我的", systemImage: "person")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .background(Color.white.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: -2)

            VStack(spacing: 6) {
                Button {
                    selectedTab = .ai
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.10, green: 0.45, blue: 0.91),
                                    Color(red: 0.26, green: 0.52, blue: 0.96)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                        .shadow(color: Color.blue.opacity(0.35), radius: 20, x: 0, y: 10)
                }
                Text("AI 助手")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.10, green: 0.45, blue: 0.91))
            }
            .offset(y: -18)
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

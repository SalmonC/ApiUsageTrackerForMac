import SwiftUI

private let usageListCoordinateSpaceName = "usageListCoordinateSpace"
private let dragAutoScrollThrottle: TimeInterval = 0.12

struct MainView: View {
    @ObservedObject var viewModel: AppViewModel
    var onPreferredHeightChange: ((CGFloat) -> Void)? = nil
    
    @State private var measuredHeaderHeight: CGFloat = 0
    @State private var measuredSummaryHeight: CGFloat = 0
    @State private var measuredFooterHeight: CGFloat = 0
    @State private var measuredListContentHeight: CGFloat = 0
    @State private var lastReportedPreferredHeight: CGFloat = 0
    @State private var pendingHeightReport: DispatchWorkItem?
    @State private var draggedAccountID: UUID?
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var usageListViewportHeight: CGFloat = 0
    @State private var lastAutoScrollAt: Date = .distantPast

    private var language: AppLanguage {
        viewModel.settings.language
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            if viewModel.isLoading {
                loadingView
            } else if viewModel.usageData.isEmpty {
                emptyView
            } else {
                VStack(spacing: 0) {
                    summaryBar
                    usageListView
                }
            }
            
            Divider()
            
            footerView
        }
        .onAppear {
            schedulePreferredHeightReport(immediate: true)
            schedulePreferredHeightReport(delay: 0.18)
        }
        .onChange(of: viewModel.isLoading) { _, _ in
            schedulePreferredHeightReport(immediate: true)
            schedulePreferredHeightReport(delay: 0.18)
        }
        .onChange(of: viewModel.usageData.map(\.accountId)) { _, _ in
            let currentIDs = Set(viewModel.usageData.map(\.accountId))
            rowFrames = rowFrames.filter { currentIDs.contains($0.key) }
            if let draggedAccountID, !currentIDs.contains(draggedAccountID) {
                endRowDrag()
            }
            schedulePreferredHeightReport(immediate: true)
            schedulePreferredHeightReport(delay: 0.18)
        }
        .onChange(of: viewModel.usageData.map(\.lastUpdated)) { _, _ in
            schedulePreferredHeightReport(delay: 0.12)
        }
        .onChange(of: draggedAccountID) { _, newValue in
            if newValue == nil {
                lastAutoScrollAt = .distantPast
            }
        }
        .onPreferenceChange(MainViewHeightPreferenceKey.self) { heights in
            measuredHeaderHeight = heights[MainViewMeasuredSection.header] ?? measuredHeaderHeight
            measuredSummaryHeight = heights[MainViewMeasuredSection.summary] ?? measuredSummaryHeight
            measuredFooterHeight = heights[MainViewMeasuredSection.footer] ?? measuredFooterHeight
            measuredListContentHeight = heights[MainViewMeasuredSection.list] ?? measuredListContentHeight
            schedulePreferredHeightReport(delay: 0.08)
        }
        .onPreferenceChange(UsageRowFramePreferenceKey.self) { frames in
            rowFrames.merge(frames, uniquingKeysWith: { _, new in new })
        }
        .onPreferenceChange(UsageListViewportHeightPreferenceKey.self) { viewportHeight in
            usageListViewportHeight = viewportHeight
        }
        .onDisappear {
            pendingHeightReport?.cancel()
            pendingHeightReport = nil
            endRowDrag()
            rowFrames = [:]
            usageListViewportHeight = 0
            lastAutoScrollAt = .distantPast
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(.blue)
            Text("QuotaPulse")
                .font(.headline)
            Spacer()
            Button(action: {
                Task {
                    await viewModel.refreshAll()
                }
            }) {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isLoading)
        }
        .padding()
        .measureHeight(for: .header)
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text(language == .english ? "Refreshing..." : "刷新中...")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(height: 200)
    }
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "key.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(language == .english ? "No API Accounts Configured" : "未配置 API 账号")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(language == .english ? "Right-click icon → Settings to add accounts" : "右键菜单栏图标 → 设置，添加账号")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button(language == .english ? "Open Settings" : "打开设置") {
                    viewModel.openSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button(language == .english ? "Refresh" : "刷新") {
                    Task { await viewModel.refreshAll() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
        }
        .frame(height: 200)
    }

    private var summaryBar: some View {
        HStack(spacing: 10) {
            summaryChip(
                text: language == .english ? "\(viewModel.usageData.count) items" : "\(viewModel.usageData.count)项",
                icon: "tray.full",
                color: .secondary
            )

            summaryChip(
                text: viewModel.failedAccountCount > 0
                    ? (language == .english ? "\(viewModel.failedAccountCount) issues" : "\(viewModel.failedAccountCount) 异常")
                    : (language == .english ? "All healthy" : "全部正常"),
                icon: viewModel.failedAccountCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                color: viewModel.failedAccountCount > 0 ? .orange : .green
            )

            Spacer()

            Menu {
                ForEach(DashboardSortMode.allCases) { mode in
                    Button {
                        viewModel.setDashboardSortMode(mode)
                    } label: {
                        HStack {
                            Text(mode.displayName(language: language))
                            if mode == viewModel.dashboardSortMode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: sortModeIconName(viewModel.dashboardSortMode))
                    Text(viewModel.dashboardSortMode.displayName(language: language))
                }
            }
            .menuStyle(.borderlessButton)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .measureHeight(for: .summary)
    }
    
    private var usageListView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.displayUsageData, id: \.accountId) { data in
                        UsageRowView(
                            data: data,
                            language: language,
                            isRefreshing: viewModel.refreshingAccountIDs.contains(data.accountId),
                            canManualReorder: viewModel.dashboardSortMode == .manual,
                            isDragSource: draggedAccountID == data.accountId,
                            onRetry: {
                                Task {
                                    await viewModel.refreshAccount(data.accountId)
                                }
                            },
                            onDragChanged: { value in
                                handleRowDragChanged(
                                    accountID: data.accountId,
                                    pointerYInList: value,
                                    scrollProxy: scrollProxy
                                )
                            },
                            onDragEnded: {
                                endRowDrag()
                            }
                        )
                        .id(data.accountId)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: UsageRowFramePreferenceKey.self,
                                    value: [data.accountId: proxy.frame(in: .named(usageListCoordinateSpaceName))]
                                )
                            }
                        )
                    }
                }
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.9), value: viewModel.dashboardManualOrder)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .measureHeight(for: .list)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: UsageListViewportHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            )
            .coordinateSpace(name: usageListCoordinateSpaceName)
            .frame(maxWidth: .infinity)
            .clipped()
        }
    }
    
    private var footerView: some View {
        HStack {
            if let lastUpdate = viewModel.latestUpdateTime {
                Text(language == .english ? "Updated \(formattedTime(lastUpdate))" : "更新于 \(formattedTime(lastUpdate))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if viewModel.secondsUntilDataRefresh > 0 {
                Text("·")
                .font(.caption2)
                .foregroundColor(.secondary)
                Text(language == .english
                     ? "Next data refresh \(formattedCountdown(viewModel.secondsUntilDataRefresh))"
                     : "下次数据刷新 \(formattedCountdown(viewModel.secondsUntilDataRefresh))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                viewModel.openSettings()
            }) {
                Image(systemName: "gear")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help(language == .english ? "Settings" : "设置")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .measureHeight(for: .footer)
    }

    private func summaryChip(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .foregroundColor(color)
        .clipShape(Capsule())
    }

    private func sortModeIconName(_ mode: DashboardSortMode) -> String {
        switch mode {
        case .manual:
            return "line.3.horizontal.circle"
        case .risk:
            return "exclamationmark.shield"
        case .provider:
            return "square.grid.2x2"
        case .name:
            return "textformat.abc"
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formattedCountdown(_ totalSeconds: Int) -> String {
        let seconds = max(totalSeconds, 0)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainSeconds = seconds % 60

        if hours > 0 {
            return language == .english ? "\(hours)h \(minutes)m" : "\(hours)小时 \(minutes)分"
        }
        if minutes > 0 {
            return language == .english ? "\(minutes)m \(remainSeconds)s" : "\(minutes)分 \(remainSeconds)秒"
        }
        return language == .english ? "\(remainSeconds)s" : "\(remainSeconds)秒"
    }

    private func triggerAutoScrollIfNeeded(
        dragMidY: CGFloat,
        scrollProxy: ScrollViewProxy
    ) {
        guard viewModel.dashboardSortMode == .manual else { return }
        guard usageListViewportHeight > 0 else { return }
        guard let draggedAccountID else { return }

        let now = Date()
        guard now.timeIntervalSince(lastAutoScrollAt) >= dragAutoScrollThrottle else { return }

        let orderedIDs = viewModel.displayUsageData.map(\.accountId)
        guard let draggedIndex = orderedIDs.firstIndex(of: draggedAccountID) else { return }

        let edgeInset = max(24, min(56, usageListViewportHeight * 0.16))

        var destinationID: UUID
        var anchor: UnitPoint = .center

        if dragMidY <= edgeInset {
            destinationID = draggedIndex > 0 ? orderedIDs[draggedIndex - 1] : orderedIDs[draggedIndex]
            anchor = .top
        } else if dragMidY >= usageListViewportHeight - edgeInset {
            destinationID = draggedIndex + 1 < orderedIDs.count ? orderedIDs[draggedIndex + 1] : orderedIDs[draggedIndex]
            anchor = .bottom
        } else {
            return
        }

        lastAutoScrollAt = now

        withAnimation(.easeOut(duration: 0.14)) {
            scrollProxy.scrollTo(destinationID, anchor: anchor)
        }
    }

    private func handleRowDragChanged(
        accountID: UUID,
        pointerYInList: CGFloat,
        scrollProxy: ScrollViewProxy
    ) {
        guard viewModel.dashboardSortMode == .manual else { return }
        if draggedAccountID != accountID {
            draggedAccountID = accountID
            lastAutoScrollAt = .distantPast
        }
        reorderDraggedRowIfNeeded(draggedID: accountID, pointerYInList: pointerYInList)
        triggerAutoScrollIfNeeded(dragMidY: pointerYInList, scrollProxy: scrollProxy)
    }

    private func reorderDraggedRowIfNeeded(draggedID: UUID, pointerYInList: CGFloat) {
        let orderedIDs = viewModel.displayUsageData.map(\.accountId)
        guard orderedIDs.contains(draggedID) else { return }

        let idsWithoutDragged = orderedIDs.filter { $0 != draggedID }
        guard !idsWithoutDragged.isEmpty else { return }

        var insertionIndex = idsWithoutDragged.count
        for (index, candidateID) in idsWithoutDragged.enumerated() {
            guard let candidateFrame = rowFrames[candidateID] else { continue }
            if pointerYInList < candidateFrame.midY {
                insertionIndex = index
                break
            }
        }

        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.9)) {
            if insertionIndex < idsWithoutDragged.count {
                _ = viewModel.moveManualOrder(draggedID: draggedID, before: idsWithoutDragged[insertionIndex])
            } else if let lastID = idsWithoutDragged.last {
                _ = viewModel.moveManualOrder(draggedID: draggedID, after: lastID)
            }
        }
    }

    private func endRowDrag() {
        guard draggedAccountID != nil else { return }
        draggedAccountID = nil
        lastAutoScrollAt = .distantPast
        viewModel.commitManualOrderFromCurrentDisplayIfNeeded()
    }
    
    private func reportPreferredHeightIfNeeded() {
        guard let onPreferredHeightChange else { return }
        
        let header = max(measuredHeaderHeight, 48)
        let footer = max(measuredFooterHeight, 28)
        let dividerHeights: CGFloat = 2
        let summary = viewModel.isLoading || viewModel.usageData.isEmpty ? 0 : max(measuredSummaryHeight, 0)
        let safetyPadding: CGFloat = 8
        
        let contentHeight: CGFloat
        if viewModel.isLoading || viewModel.usageData.isEmpty {
            contentHeight = 200
        } else {
            contentHeight = max(measuredListContentHeight, 80)
        }
        
        let preferredHeight = header + dividerHeights + summary + contentHeight + footer + safetyPadding
        let reportThreshold: CGFloat = 1.0
        guard abs(preferredHeight - lastReportedPreferredHeight) > reportThreshold else { return }
        
        lastReportedPreferredHeight = preferredHeight
        onPreferredHeightChange(preferredHeight)
    }
    
    private func schedulePreferredHeightReport(immediate: Bool = false, delay: TimeInterval = 0) {
        if immediate {
            pendingHeightReport?.cancel()
            pendingHeightReport = nil
            reportPreferredHeightIfNeeded()
            return
        }

        pendingHeightReport?.cancel()
        
        let work = DispatchWorkItem {
            reportPreferredHeightIfNeeded()
        }
        pendingHeightReport = work
        
        let actualDelay = immediate ? 0 : delay
        DispatchQueue.main.asyncAfter(deadline: .now() + actualDelay, execute: work)
    }
}

private enum MainViewMeasuredSection: Hashable {
    case header
    case summary
    case footer
    case list
}

private struct MainViewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [MainViewMeasuredSection: CGFloat] = [:]
    
    static func reduce(value: inout [MainViewMeasuredSection: CGFloat], nextValue: () -> [MainViewMeasuredSection: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct UsageRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct UsageListViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    func measureHeight(for section: MainViewMeasuredSection) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: MainViewHeightPreferenceKey.self,
                        value: [section: proxy.size.height]
                    )
            }
        )
    }
}

private struct UsageRowView: View {
    let data: UsageData
    let language: AppLanguage
    var isRefreshing: Bool = false
    var canManualReorder: Bool = false
    var isDragSource: Bool = false
    var onRetry: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: quotaCycles.count > 1 ? 6 : 4) {
                topRow

                if let error = data.errorMessage {
                    errorRow(error)
                } else {
                    quotaCycleRows
                }
            }

            Spacer(minLength: 6)
            trailingStatus
                .frame(minWidth: 48, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, quotaCycles.count > 1 ? 8 : 6)
        .background(Color(NSColor.controlBackgroundColor))
        .opacity(isDragSource ? 0.78 : 1.0)
        .scaleEffect(isDragSource ? 0.992 : 1.0)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.18), lineWidth: 1)
        )
        .shadow(
            color: (isDragSource ? Color.accentColor : .black).opacity(isDragSource ? 0.16 : 0.03),
            radius: isDragSource ? 8 : 2,
            x: 0,
            y: isDragSource ? 5 : 1
        )
        .zIndex(isDragSource ? 2 : 0)
        .animation(.easeOut(duration: 0.12), value: isDragSource)
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            if canManualReorder {
                dragHandle
            }

            ZStack {
                Circle()
                    .fill(providerColor.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: data.provider.icon)
                    .font(.system(size: 13))
                    .foregroundColor(providerColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(data.accountName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if shouldShowProviderSubtitle {
                    HStack(spacing: 6) {
                        Text(data.provider.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 6)
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if isRefreshing {
            ProgressView().scaleEffect(0.75)
        } else if data.errorMessage != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))
        } else if dualRingCycles.count >= 2 {
            HStack(spacing: 8) {
                ForEach(dualRingCycles.prefix(2)) { cycle in
                    VStack(spacing: 3) {
                        RemainingRingView(
                            percentage: cycle.remainingPercentage ?? 0,
                            tint: ringColor(for: cycle.remainingPercentage ?? 0),
                            size: 46,
                            fontSize: 10,
                            language: language
                        )
                        if let label = cycleLabel(for: cycle) {
                            Text(label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        } else if let remainingPercent = preferredRingCycle?.remainingPercentage {
            RemainingRingView(
                percentage: remainingPercent,
                tint: ringColor(for: remainingPercent),
                language: language
            )
        } else if let plan = data.displaySubscriptionPlan, data.provider == .chatGPT {
            Text(plan)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.14))
                .foregroundColor(.green)
                .cornerRadius(6)
        } else if data.tokenRemaining != nil {
            Text(data.displayRemaining)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(remainingColor)
        } else {
            Text("--")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func errorRow(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
            Text(error)
                .font(.caption)
                .lineLimit(1)
                .foregroundColor(.primary)
            Spacer(minLength: 6)
            if let onRetry {
                Button(action: onRetry) {
                    Image(systemName: isRefreshing ? "hourglass" : "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .help(language == .english ? "Retry" : "重试")
            }
        }
    }

    @ViewBuilder
    private var quotaCycleRows: some View {
        if quotaCycles.isEmpty {
            Text(language == .english ? "No usage data yet" : "暂无用量统计")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(quotaCycles) { cycle in
                    quotaCycleRow(cycle)
                }
            }
        }
    }

    private func quotaCycleRow(_ cycle: QuotaCycle) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 6) {
                if let cycleLabel = cycleLabel(for: cycle) {
                    Text(cycleLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(providerColor.opacity(0.14))
                        .foregroundColor(providerColor)
                        .cornerRadius(5)
                }

                let usageText = cycleUsageText(cycle)
                if !usageText.isEmpty {
                    Text(usageText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)
                if !hasRingIndicator, let remainingPercent = cycle.remainingPercentage {
                    Text(language == .english ? "Left \(formatPercent(remainingPercent))" : "余 \(formatPercent(remainingPercent))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(ringColor(for: remainingPercent))
                }
            }

            if let reset = cycle.reset, let countdown = countdownString(for: reset) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(
                        cycle.isResetEstimated
                        ? (language == .english ? "Est. \(resetVerb(for: cycle)) in \(countdown)" : "预计 \(countdown) 后\(resetVerb(for: cycle))")
                        : (language == .english ? "\(resetVerb(for: cycle)) in \(countdown)" : "\(countdown) \(resetVerb(for: cycle))")
                    )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            } else if let unavailable = refreshUnavailableText(for: cycle) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.75))
                    Text(unavailable)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var dragHandle: some View {
        if let onDragChanged, let onDragEnded {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 16, height: 16)
                .help(language == .english ? "Drag to reorder" : "拖动调整顺序")
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named(usageListCoordinateSpaceName))
                        .onChanged { value in
                            onDragChanged(value.location.y)
                        }
                        .onEnded { _ in onDragEnded() }
                )
        }
    }

    private var providerColor: Color {
        switch data.provider {
        case .miniMax:
            return .purple
        case .glm:
            return .blue
        case .tavily:
            return .green
        case .openAI:
            return .teal
        case .chatGPT:
            return .pink
        case .kimi:
            return .indigo
        }
    }

    private var shouldShowProviderSubtitle: Bool {
        normalizedLabel(data.accountName) != normalizedLabel(data.provider.displayName)
    }

    private func normalizedLabel(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private var hasRingIndicator: Bool {
        preferredRingCycle?.remainingPercentage != nil
    }

    private var dualRingCycles: [QuotaCycle] {
        guard quotaCycles.count >= 2 else { return [] }
        return quotaCycles
            .filter { $0.remainingPercentage != nil }
            .sorted { lhs, rhs in
                ringSortWeight(lhs) < ringSortWeight(rhs)
            }
    }

    private var remainingColor: Color {
        if data.tokenTotal != nil && data.tokenTotal! > 0 {
            let pct = data.usagePercentage
            if pct > 90 {
                return .red
            } else if pct > 70 {
                return .orange
            } else if pct > 50 {
                return .yellow
            }
        }
        return .green
    }
    
    private func countdownString(for refreshTime: Date) -> String? {
        let now = Date()
        guard refreshTime > now else { return nil }
        
        let seconds = Int(refreshTime.timeIntervalSince(now))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainSeconds = seconds % 60
        
        if hours > 24 {
            let days = hours / 24
            return language == .english ? "\(days)d \(hours % 24)h" : "\(days)天 \(hours % 24)小时"
        } else if hours > 0 {
            return language == .english ? "\(hours)h \(minutes)m" : "\(hours)小时 \(minutes)分"
        } else if minutes > 0 {
            return language == .english ? "\(minutes)m" : "\(minutes)分"
        } else {
            return language == .english ? "\(remainSeconds)s" : "\(remainSeconds)秒"
        }
    }

    private func formatValue(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fK", value / 1000)
        }
        return String(format: "%.0f", value)
    }

    private func formatPercent(_ value: Double) -> String {
        let normalized = min(max(value, 0), 100)
        if normalized >= 10 || abs(normalized.rounded() - normalized) < 0.05 {
            return "\(Int(normalized.rounded()))%"
        }
        return String(format: "%.1f%%", normalized)
    }

    private var quotaCycles: [QuotaCycle] {
        var cycles: [QuotaCycle] = []
        let primary = QuotaCycle(
            source: .primary,
            used: data.tokenUsed,
            total: data.tokenTotal,
            remaining: data.tokenRemaining,
            reset: data.refreshTime ?? data.nextRefreshTime,
            isPercentageOnly: data.primaryCycleIsPercentage == true,
            isResetEstimated: data.primaryRefreshIsEstimated
        )
        let secondary = QuotaCycle(
            source: .secondary,
            used: data.monthlyUsed,
            total: data.monthlyTotal,
            remaining: data.monthlyRemaining,
            reset: data.monthlyRefreshTime,
            isPercentageOnly: data.secondaryCycleIsPercentage == true,
            isResetEstimated: data.secondaryRefreshIsEstimated
        )

        if primary.hasData {
            cycles.append(primary)
        }
        if secondary.hasData && !isSameCycle(primary, secondary) {
            cycles.append(secondary)
        }
        return cycles
    }

    private var preferredRingCycle: QuotaCycle? {
        let candidates = quotaCycles.compactMap { cycle -> (QuotaCycle, Double)? in
            guard let remaining = cycle.remainingPercentage else { return nil }
            return (cycle, remaining)
        }
        guard !candidates.isEmpty else { return nil }

        let now = Date()
        return candidates.min { lhs, rhs in
            if abs(lhs.1 - rhs.1) > 0.01 {
                return lhs.1 < rhs.1
            }
            return resetPriority(lhs.0.reset, now: now) < resetPriority(rhs.0.reset, now: now)
        }?.0
    }

    private func isSameCycle(_ lhs: QuotaCycle, _ rhs: QuotaCycle) -> Bool {
        valuesClose(lhs.used, rhs.used) &&
        valuesClose(lhs.total, rhs.total) &&
        valuesClose(lhs.remaining, rhs.remaining) &&
        datesClose(lhs.reset, rhs.reset)
    }

    private func valuesClose(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (l?, r?):
            return abs(l - r) < 0.0001
        default:
            return false
        }
    }

    private func datesClose(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (l?, r?):
            return abs(l.timeIntervalSince(r)) < 60
        default:
            return false
        }
    }

    private func cycleLabel(for cycle: QuotaCycle) -> String? {
        if data.provider == .chatGPT,
           cycle.used == nil,
           cycle.total == nil,
           cycle.remaining == nil {
            return language == .english ? "Subscription" : "订阅"
        }

        guard quotaCycles.count > 1 else { return nil }
        if let shortSource = shortCycleSource {
            return cycle.source == shortSource
                ? (language == .english ? "Short" : "短周期")
                : (language == .english ? "Long" : "长周期")
        }
        return cycle.source == .primary ? (language == .english ? "Cycle A" : "周期A") : (language == .english ? "Cycle B" : "周期B")
    }

    private var shortCycleSource: QuotaCycle.Source? {
        let candidates = quotaCycles.compactMap { cycle -> (QuotaCycle.Source, Date)? in
            guard let reset = cycle.reset else { return nil }
            return (cycle.source, reset)
        }
        guard candidates.count >= 2 else { return nil }
        let now = Date()
        return candidates.min { lhs, rhs in
            resetPriority(lhs.1, now: now) < resetPriority(rhs.1, now: now)
        }?.0
    }

    private func resetPriority(_ date: Date?, now: Date) -> TimeInterval {
        guard let date else { return .greatestFiniteMagnitude }
        let delta = date.timeIntervalSince(now)
        if delta >= 0 {
            return delta
        }
        return abs(delta) + 86_400
    }

    private func cycleUsageText(_ cycle: QuotaCycle) -> String {
        if data.provider == .chatGPT,
           cycle.used == nil,
           cycle.total == nil,
           cycle.remaining == nil {
            return language == .english ? "Status normal" : "状态正常"
        }

        if data.provider == .kimi, cycle.isPercentageOnly {
            return ""
        }

        if cycle.isPercentageOnly {
            let usedText = cycle.used.map(formatPercent)
            let remainingText = cycle.remaining.map(formatPercent)

            if let usedText, let remainingText {
                return language == .english ? "\(usedText) · left \(remainingText)" : "\(usedText) · 余 \(remainingText)"
            }
            if let remainingText {
                return language == .english ? "left \(remainingText)" : "余 \(remainingText)"
            }
            if let usedText {
                return usedText
            }
            return "--"
        }

        let usedText = cycle.used.map(formatValue)
        let totalText = cycle.total.map(formatValue)
        let remainingText = cycle.remaining.map(formatValue)

        if let usedText, let totalText {
            return language == .english ? "Used \(usedText)/\(totalText)" : "已使用 \(usedText)/\(totalText)"
        }
        if let remainingText {
            return language == .english ? "left \(remainingText)" : "余 \(remainingText)"
        }
        if let usedText {
            return language == .english ? "Used \(usedText)" : "已使用 \(usedText)"
        }
        if let totalText {
            return totalText
        }
        return "--"
    }

    private func resetVerb(for cycle: QuotaCycle) -> String {
        if data.provider == .chatGPT,
           cycle.used == nil,
           cycle.total == nil,
           cycle.remaining == nil {
            return language == .english ? "renews" : "续期"
        }
        return language == .english ? "resets" : "重置"
    }

    private func refreshUnavailableText(for cycle: QuotaCycle) -> String? {
        guard cycle.reset == nil else { return nil }
        if data.provider == .tavily {
            return language == .english ? "Reset time unavailable" : "刷新时间未知"
        }
        return nil
    }

    private func ringSortWeight(_ cycle: QuotaCycle) -> Int {
        if let shortSource = shortCycleSource {
            return cycle.source == shortSource ? 1 : 0
        }
        return cycle.source == .primary ? 0 : 1
    }

    private func ringColor(for remaining: Double) -> Color {
        if remaining <= 20 { return .red }
        if remaining <= 50 { return .orange }
        if remaining <= 70 { return .yellow }
        return .green
    }

    private struct QuotaCycle: Identifiable {
        enum Source: String {
            case primary
            case secondary
        }

        let source: Source
        let used: Double?
        let total: Double?
        let remaining: Double?
        let reset: Date?
        let isPercentageOnly: Bool
        let isResetEstimated: Bool

        var id: String { source.rawValue }

        var hasData: Bool {
            used != nil || total != nil || remaining != nil || reset != nil
        }

        var usedPercentage: Double? {
            if let used, let total, total > 0 {
                return min(max(used / total * 100, 0), 100)
            }
            if isPercentageOnly {
                if let used {
                    return min(max(used, 0), 100)
                }
                if let remaining {
                    return min(max(100 - remaining, 0), 100)
                }
            }
            return nil
        }

        var remainingPercentage: Double? {
            if let remaining, let total, total > 0 {
                return min(max(remaining / total * 100, 0), 100)
            }
            if let used, let total, total > 0 {
                return min(max(100 - used / total * 100, 0), 100)
            }
            if isPercentageOnly {
                if let remaining {
                    return min(max(remaining, 0), 100)
                }
                if let used {
                    return min(max(100 - used, 0), 100)
                }
            }
            return nil
        }
    }
}

private struct RemainingRingView: View {
    let percentage: Double
    let tint: Color
    var size: CGFloat = 42
    var fontSize: CGFloat = 10
    var language: AppLanguage = .chinese

    var body: some View {
        let normalized = min(max(percentage, 0), 100)

        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 3.5)

            Circle()
                .trim(from: 0, to: normalized / 100)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int(normalized.rounded()))%")
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(width: size, height: size)
        .help(language == .english ? "Remaining \(Int(normalized.rounded()))%" : "剩余 \(Int(normalized.rounded()))%")
        .accessibilityLabel(Text(language == .english ? "Remaining \(Int(normalized.rounded()))%" : "剩余 \(Int(normalized.rounded()))%"))
    }
}

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
            Text("API Usage")
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
            Text("Refreshing...")
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
            Text("No API Accounts Configured")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Right-click icon → Settings to add accounts")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button("Open Settings") {
                    viewModel.openSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button("Refresh") {
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
        HStack(spacing: 8) {
            Label("\(viewModel.usageData.count) accounts", systemImage: "tray.full")
                .foregroundColor(.secondary)

            if viewModel.failedAccountCount > 0 {
                Label("\(viewModel.failedAccountCount) failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            } else {
                Label("All healthy", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

            Spacer()

            if viewModel.dashboardSortMode == .manual {
                Text("拖动手柄调整顺序")
                    .foregroundColor(.secondary)
            }

            Menu {
                ForEach(DashboardSortMode.allCases) { mode in
                    Button {
                        viewModel.setDashboardSortMode(mode)
                    } label: {
                        HStack {
                            Text(mode.displayName)
                            if mode == viewModel.dashboardSortMode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down.circle")
                    Text(viewModel.dashboardSortMode.displayName)
                }
            }
            .menuStyle(.borderlessButton)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .measureHeight(for: .summary)
    }
    
    private var usageListView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.displayUsageData, id: \.accountId) { data in
                        UsageRowView(
                            data: data,
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
                Text("Updated: \(formattedTime(lastUpdate))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if viewModel.secondsUntilTokenRefresh > 0 {
                Text("·")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Next refresh in \(formattedCountdown(viewModel.secondsUntilTokenRefresh))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if !viewModel.usageData.isEmpty {
                Text("·")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(viewModel.failedAccountCount > 0 ? "\(viewModel.failedAccountCount) failed" : "OK")
                    .font(.caption2)
                    .foregroundColor(viewModel.failedAccountCount > 0 ? .orange : .green)
            }
            Spacer()
            Button(action: {
                viewModel.openSettings()
            }) {
                Image(systemName: "gear")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .measureHeight(for: .footer)
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
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainSeconds)s"
        }
        return "\(remainSeconds)s"
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
    var isRefreshing: Bool = false
    var canManualReorder: Bool = false
    var isDragSource: Bool = false
    var onRetry: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topRow

            if let error = data.errorMessage {
                errorRow(error)
            } else {
                quotaCycleRows
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
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
                    .frame(width: 28, height: 28)
                Image(systemName: data.provider.icon)
                    .font(.system(size: 12))
                    .foregroundColor(providerColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(data.accountName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(data.provider.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if let plan = data.displaySubscriptionPlan, data.provider == .chatGPT {
                        Text(plan)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.14))
                            .foregroundColor(.green)
                            .cornerRadius(5)
                    }
                }
            }

            Spacer(minLength: 6)
            trailingStatus
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
        } else if data.tokenRemaining != nil {
            Text(data.displayRemaining)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(remainingColor)
        } else if let plan = data.displaySubscriptionPlan, data.provider == .chatGPT {
            Text(plan)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.green)
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
                .help("重试")
            }
        }
    }

    @ViewBuilder
    private var quotaCycleRows: some View {
        if quotaCycles.isEmpty {
            Text("暂无用量统计")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(quotaCycles) { cycle in
                    quotaCycleRow(cycle)
                }
            }
        }
    }

    private func quotaCycleRow(_ cycle: QuotaCycle) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("\(cycleLabel(for: cycle)): \(cycleUsageText(cycle))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if let percentage = cycle.percentage {
                    Text("\(Int(percentage))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(percentageColor(percentage))
                }
            }

            if let reset = cycle.reset {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("重置: \(formattedDate(reset))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if let countdown = countdownString(for: reset) {
                        Text("(\(countdown))")
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
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
                .help("拖动调整顺序")
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
        
        if hours > 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatValue(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fK", value / 1000)
        }
        return String(format: "%.0f", value)
    }

    private var quotaCycles: [QuotaCycle] {
        var cycles: [QuotaCycle] = []
        let primary = QuotaCycle(
            source: .primary,
            used: data.tokenUsed,
            total: data.tokenTotal,
            remaining: data.tokenRemaining,
            reset: data.refreshTime ?? data.nextRefreshTime
        )
        let secondary = QuotaCycle(
            source: .secondary,
            used: data.monthlyUsed,
            total: data.monthlyTotal,
            remaining: data.monthlyRemaining,
            reset: data.monthlyRefreshTime
        )

        if primary.hasData {
            cycles.append(primary)
        }
        if secondary.hasData && !isSameCycle(primary, secondary) {
            cycles.append(secondary)
        }
        return cycles
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

    private func cycleLabel(for cycle: QuotaCycle) -> String {
        guard quotaCycles.count > 1 else { return "周期" }
        if let shortSource = shortCycleSource {
            return cycle.source == shortSource ? "短周期" : "长周期"
        }
        return cycle.source == .primary ? "周期A" : "周期B"
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

    private func resetPriority(_ date: Date, now: Date) -> TimeInterval {
        let delta = date.timeIntervalSince(now)
        if delta >= 0 {
            return delta
        }
        return abs(delta) + 86_400
    }

    private func cycleUsageText(_ cycle: QuotaCycle) -> String {
        let usedText = cycle.used.map(formatValue)
        let totalText = cycle.total.map(formatValue)
        let remainingText = cycle.remaining.map(formatValue)

        if let usedText, let totalText, let remainingText {
            return "已用 \(usedText)/\(totalText) · 余 \(remainingText)"
        }
        if let usedText, let totalText {
            return "已用 \(usedText)/\(totalText)"
        }
        if let remainingText {
            return "剩余 \(remainingText)"
        }
        if let usedText {
            return "已用 \(usedText)"
        }
        if let totalText {
            return "总额 \(totalText)"
        }
        return "暂无额度数据"
    }

    private func percentageColor(_ value: Double) -> Color {
        if value > 90 { return .red }
        if value > 70 { return .orange }
        if value > 50 { return .yellow }
        return .blue
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

        var id: String { source.rawValue }

        var hasData: Bool {
            used != nil || total != nil || remaining != nil || reset != nil
        }

        var percentage: Double? {
            guard let used, let total, total > 0 else { return nil }
            return min(max(used / total * 100, 0), 100)
        }
    }
}

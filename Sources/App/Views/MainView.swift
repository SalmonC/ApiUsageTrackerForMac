import SwiftUI

private let popoverSynchronizedResizeDuration: TimeInterval = 0.24
private let popoverSynchronizedResizeAnimation = Animation.easeInOut(duration: popoverSynchronizedResizeDuration)
private let popoverSynchronizedResizeTrailingGrace: TimeInterval = 0.24
private let usageListCoordinateSpaceName = "usageListCoordinateSpace"
private let dragAutoScrollThrottle: TimeInterval = 0.12

struct MainView: View {
    @ObservedObject var viewModel: AppViewModel
    var onPreferredHeightChange: ((CGFloat) -> Void)? = nil
    var onExpansionAnimationPhaseChange: ((Bool) -> Void)? = nil
    
    @State private var measuredHeaderHeight: CGFloat = 0
    @State private var measuredSummaryHeight: CGFloat = 0
    @State private var measuredFooterHeight: CGFloat = 0
    @State private var measuredListContentHeight: CGFloat = 0
    @State private var lastReportedPreferredHeight: CGFloat = 0
    @State private var pendingHeightReport: DispatchWorkItem?
    @State private var pendingExpansionAnimationEnd: DispatchWorkItem?
    @State private var isSynchronizingExpansionResize = false
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
            if isSynchronizingExpansionResize {
                refreshSynchronizedExpansionResizePhase()
                schedulePreferredHeightReport(immediate: true)
            } else {
                schedulePreferredHeightReport(delay: 0.10)
            }
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
            pendingExpansionAnimationEnd?.cancel()
            pendingExpansionAnimationEnd = nil
            if isSynchronizingExpansionResize {
                isSynchronizingExpansionResize = false
                onExpansionAnimationPhaseChange?(false)
            }
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
            ScrollView(.vertical, showsIndicators: !isSynchronizingExpansionResize) {
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
                            onExpansionAnimationTriggered: {
                                beginSynchronizedExpansionResize()
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
        let reportThreshold: CGFloat = isSynchronizingExpansionResize ? 0.35 : 1.0
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

    private func beginSynchronizedExpansionResize() {
        if !isSynchronizingExpansionResize {
            isSynchronizingExpansionResize = true
            onExpansionAnimationPhaseChange?(true)
        }

        schedulePreferredHeightReport(immediate: true)

        pendingExpansionAnimationEnd?.cancel()
        let endWork = DispatchWorkItem {
            isSynchronizingExpansionResize = false
            onExpansionAnimationPhaseChange?(false)
            schedulePreferredHeightReport(delay: 0.02)
        }
        pendingExpansionAnimationEnd = endWork
        DispatchQueue.main.asyncAfter(
            deadline: .now() + popoverSynchronizedResizeDuration + 0.05,
            execute: endWork
        )
    }

    private func refreshSynchronizedExpansionResizePhase() {
        guard isSynchronizingExpansionResize else { return }
        onExpansionAnimationPhaseChange?(true)

        pendingExpansionAnimationEnd?.cancel()
        let endWork = DispatchWorkItem {
            isSynchronizingExpansionResize = false
            onExpansionAnimationPhaseChange?(false)
            schedulePreferredHeightReport(delay: 0.02)
        }
        pendingExpansionAnimationEnd = endWork
        DispatchQueue.main.asyncAfter(
            deadline: .now() + popoverSynchronizedResizeTrailingGrace,
            execute: endWork
        )
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
    var onExpansionAnimationTriggered: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row - always visible
            HStack(spacing: 10) {
                // Expand/collapse button
                Button(action: {
                    toggleExpanded()
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if canManualReorder {
                    dragHandle
                }
                
                // Provider icon
                ZStack {
                    Circle()
                        .fill(providerColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: data.provider.icon)
                        .font(.system(size: 14))
                        .foregroundColor(providerColor)
                }
                
                // Account name
                Text(data.accountName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Spacer(minLength: 8)
                
                // Status indicator (right side)
                VStack(alignment: .trailing, spacing: 2) {
                    statusIndicator
                    statusLabel
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(headerBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleExpanded()
            }
            
            // Expandable content
            if isExpanded {
                expandedContent
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .opacity(isDragSource ? 0.78 : 1.0)
        .scaleEffect(isDragSource ? 0.992 : 1.0)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
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

    private func toggleExpanded() {
        onExpansionAnimationTriggered?()
        withAnimation(popoverSynchronizedResizeAnimation) {
            isExpanded.toggle()
        }
    }
    
    // MARK: - Header Components
    
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
    
    @ViewBuilder
    private var statusIndicator: some View {
        if isRefreshing {
            ProgressView()
                .scaleEffect(0.7)
        } else if let error = data.errorMessage {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))
                .help(error)
        } else if let plan = data.displaySubscriptionPlan, data.provider == .chatGPT, data.tokenRemaining == nil {
            Text(plan)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.12))
                .foregroundColor(.green)
                .cornerRadius(8)
        } else if data.tokenRemaining != nil {
            HStack(spacing: 6) {
                // Mini progress ring
                if data.tokenTotal != nil && data.tokenTotal! > 0 {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                            .frame(width: 20, height: 20)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(data.usagePercentage / 100, 1.0)))
                            .stroke(usageColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 20, height: 20)
                            .rotationEffect(.degrees(-90))
                    }
                }
                
                VStack(alignment: .trailing, spacing: 0) {
                    Text(data.displayRemaining)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(remainingColor)
                    
                    if data.tokenTotal != nil {
                        Text("\(Int(data.usagePercentage))% used")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } else {
            Text("--")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if isRefreshing {
            Text("Refreshing")
                .font(.caption2)
                .foregroundColor(.secondary)
        } else if data.errorMessage != nil {
            Text("Failed")
                .font(.caption2)
                .foregroundColor(.orange)
        } else if data.tokenTotal != nil {
            Text(riskLabel)
                .font(.caption2)
                .foregroundColor(usageColor)
        }
    }
    
    private var headerBackground: some View {
        Group {
            if isExpanded {
                Color.blue.opacity(0.05)
            } else {
                Color.clear
            }
        }
    }
    
    private var borderColor: Color {
        if isExpanded {
            return Color.blue.opacity(0.3)
        }
        return Color.gray.opacity(0.15)
    }
    
    // MARK: - Expanded Content
    
    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 12)
            
            if let error = data.errorMessage {
                errorSection(error)
            } else {
                detailsSection
            }
        }
        .padding(.bottom, 12)
    }
    
    @ViewBuilder
    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 16))
                
                Text(error)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Spacer()
            }
            
            if let onRetry = onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 4) {
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        Text(isRefreshing ? "Retrying..." : "Retry This Account")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRefreshing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
    
    @ViewBuilder
    private var detailsSection: some View {
        VStack(spacing: 12) {
            if let plan = data.displaySubscriptionPlan, data.provider == .chatGPT {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text("Subscription: \(plan)")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            
            // Stats grid
            HStack(spacing: 0) {
                if data.tokenUsed != nil {
                    StatBox(
                        title: "Used",
                        value: data.displayUsed,
                        icon: "arrow.down.circle",
                        color: .orange
                    )
                    .frame(maxWidth: .infinity)
                }
                
                if data.tokenTotal != nil {
                    StatBox(
                        title: "Total",
                        value: data.displayTotal,
                        icon: "circle.grid.2x2",
                        color: .blue
                    )
                    .frame(maxWidth: .infinity)
                }
                
                if data.tokenRemaining != nil {
                    StatBox(
                        title: "Remaining",
                        value: data.displayRemaining,
                        icon: "checkmark.circle",
                        color: remainingColor
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            
            // Progress bar
            if data.tokenTotal != nil && data.tokenTotal! > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Usage Progress")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(data.usagePercentage))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(usageColor)
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(usageGradient)
                                .frame(width: geo.size.width * CGFloat(min(data.usagePercentage / 100, 1.0)), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
            
            // Monthly quota section (if available)
            if data.monthlyTotal != nil || data.monthlyRemaining != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Monthly Quota")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    
                    HStack(spacing: 0) {
                        if data.monthlyUsed != nil {
                            StatBox(
                                title: "Used",
                                value: data.displayMonthlyUsed,
                                icon: "arrow.down.circle.fill",
                                color: .orange
                            )
                            .frame(maxWidth: .infinity)
                        }
                        
                        if data.monthlyTotal != nil {
                            StatBox(
                                title: "Total",
                                value: data.displayMonthlyTotal,
                                icon: "calendar.circle.fill",
                                color: .blue
                            )
                            .frame(maxWidth: .infinity)
                        }
                        
                        if data.monthlyRemaining != nil {
                            StatBox(
                                title: "Remaining",
                                value: data.displayMonthlyRemaining,
                                icon: "checkmark.circle.fill",
                                color: .green
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    
                    // Monthly progress bar
                    if data.monthlyTotal != nil && data.monthlyTotal! > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Monthly Usage")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(data.monthlyUsagePercentage))%")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(monthlyUsageColor)
                            }
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.gray.opacity(0.15))
                                        .frame(height: 4)
                                    
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(monthlyUsageGradient)
                                        .frame(width: geo.size.width * CGFloat(min(data.monthlyUsagePercentage / 100, 1.0)), height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                    
                    // Monthly refresh time
                    if let monthlyRefresh = data.monthlyRefreshTime ?? data.nextRefreshTime {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("Resets: \(formattedDate(monthlyRefresh))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            if let countdown = countdownString(for: monthlyRefresh) {
                                Text("(\(countdown))")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
            
            // Refresh time
            if let refreshTime = data.refreshTime {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("Resets: \(formattedDate(refreshTime))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let countdown = countdownString(for: refreshTime) {
                        Text("(\(countdown) left)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
    
    // MARK: - Helpers
    
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
    
    private var monthlyUsageColor: Color {
        if data.monthlyUsagePercentage > 90 {
            return .red
        } else if data.monthlyUsagePercentage > 70 {
            return .orange
        } else if data.monthlyUsagePercentage > 50 {
            return .yellow
        }
        return .blue
    }
    
    private var monthlyUsageGradient: LinearGradient {
        LinearGradient(
            colors: [monthlyUsageColor.opacity(0.8), monthlyUsageColor],
            startPoint: .leading,
            endPoint: .trailing
        )
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
    
    private var usageColor: Color {
        if data.usagePercentage > 90 {
            return .red
        } else if data.usagePercentage > 70 {
            return .orange
        } else if data.usagePercentage > 50 {
            return .yellow
        }
        return .blue
    }
    
    private var usageGradient: LinearGradient {
        LinearGradient(
            colors: [usageColor.opacity(0.8), usageColor],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var riskLabel: String {
        if data.usagePercentage > 90 {
            return "High Risk"
        } else if data.usagePercentage > 70 {
            return "Warning"
        } else if data.tokenTotal != nil {
            return "Normal"
        }
        return ""
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
}

// MARK: - StatBox Component

struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.system(.callout, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

import SwiftUI

// Notification for expand/collapse state change
extension Notification.Name {
    static let usageRowExpansionChanged = Notification.Name("usageRowExpansionChanged")
}

struct MainView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            if viewModel.isLoading {
                loadingView
            } else if viewModel.usageData.isEmpty {
                emptyView
            } else {
                usageListView
            }
            
            Divider()
            
            footerView
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
            Spacer()
        }
        .frame(height: 200)
    }
    
    private var usageListView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.usageData, id: \.accountId) { data in
                    UsageRowView(data: data, onRetry: {
                        Task {
                            await viewModel.refreshAll()
                        }
                    })
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    private var footerView: some View {
        HStack {
            if let lastUpdate = viewModel.usageData.first?.lastUpdated {
                Text("Updated: \(formattedTime(lastUpdate))")
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
            .help("Settings")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private func formatCountdown(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct UsageRowView: View {
    let data: UsageData
    var onRetry: (() -> Void)?
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row - always visible
            HStack(spacing: 10) {
                // Expand/collapse button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                        NotificationCenter.default.post(name: .usageRowExpansionChanged, object: nil)
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
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
                statusIndicator
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(headerBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                    NotificationCenter.default.post(name: .usageRowExpansionChanged, object: nil)
                }
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
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Header Components
    
    @ViewBuilder
    private var statusIndicator: some View {
        if let error = data.errorMessage {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))
                .help(error)
        } else if let remaining = data.tokenRemaining {
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
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                        Text("Retry")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
    
    @ViewBuilder
    private var detailsSection: some View {
        VStack(spacing: 12) {
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

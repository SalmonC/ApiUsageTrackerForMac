import SwiftUI

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
            LazyVStack(spacing: 8) {
                ForEach(viewModel.usageData, id: \.accountId) { data in
                    UsageRowView(data: data, onRetry: {
                        Task {
                            await viewModel.refreshAll()
                        }
                    })
                }
            }
            .padding(.horizontal)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                        
                        Image(systemName: data.provider.icon)
                            .foregroundColor(.blue)
                        Text(data.accountName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                compactInfoView
            }
            
            if !isExpanded {
                collapsedInfoView
            } else {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var compactInfoView: some View {
        if let error = data.errorMessage {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .help(error)
        } else if let remaining = data.tokenRemaining {
            VStack(alignment: .trailing, spacing: 0) {
                Text(data.displayRemaining)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(remainingColor)
                if data.tokenTotal != nil {
                    Text(String(format: "%.0f%%", data.usagePercentage))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var collapsedInfoView: some View {
        HStack(spacing: 16) {
            if let used = data.tokenUsed {
                HStack(spacing: 4) {
                    Text("Used:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(data.displayUsed)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                }
            }
            
            if let total = data.tokenTotal {
                HStack(spacing: 4) {
                    Text("Total:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(data.displayTotal)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                }
            }
            
            Spacer()
            
            if data.tokenTotal != nil {
                HStack(spacing: 6) {
                    ProgressView(value: data.usagePercentage, total: 100)
                        .frame(width: 60)
                        .tint(usageColor)
                    Text(String(format: "%.0f%%", data.usagePercentage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 35, alignment: .trailing)
                }
            }
        }
        .padding(.top, 4)
    }
    
    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = data.errorMessage {
                errorContent(error)
            } else {
                normalContent
            }
        }
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private func errorContent(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
            
            if let onRetry = onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
    
    @ViewBuilder
    private var normalContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 20) {
                if data.tokenUsed != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Used")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(data.displayUsed)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                }
                
                if data.tokenTotal != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(data.displayTotal)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                }
                
                Spacer()
            }
            
            if data.tokenUsed != nil && data.tokenTotal != nil {
                HStack(spacing: 8) {
                    ProgressView(value: data.usagePercentage, total: 100)
                        .tint(usageColor)
                    Text(String(format: "%.0f%%", data.usagePercentage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            
            if let refreshTime = data.refreshTime {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("Resets: \(formattedDate(refreshTime))")
                        .font(.caption2)
                    if let countdown = countdownString(for: refreshTime) {
                        Text("(\(countdown))")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                .foregroundColor(.secondary)
            }
        }
    }
    
    private var remainingColor: Color {
        if data.tokenTotal != nil && data.tokenTotal! > 0 {
            let pct = data.usagePercentage
            if pct > 80 {
                return .red
            } else if pct > 50 {
                return .orange
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
    
    private var usageColor: Color {
        if data.usagePercentage > 80 {
            return .red
        } else if data.usagePercentage > 50 {
            return .orange
        }
        return .blue
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

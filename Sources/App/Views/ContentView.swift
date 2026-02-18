import SwiftUI

struct MainTabView: View {
    @ObservedObject var viewModel: AppViewModel
    var startAtSettings: Bool = false
    
    @State private var selectedTab: Int = 0
    
    init(viewModel: AppViewModel, startAtSettings: Bool = false) {
        self.viewModel = viewModel
        self._selectedTab = State(initialValue: startAtSettings ? 1 : 0)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            mainView
                .tabItem {
                    Label("Usage", systemImage: "chart.bar")
                }
                .tag(0)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(1)
        }
        .frame(width: 320, height: 400)
    }
    
    private var mainView: some View {
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
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isLoading)
        }
        .padding()
    }
    
    private var loadingView: some View {
        VStack {
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
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No services configured")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Go to Settings to add API keys")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(height: 200)
    }
    
    private var usageListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.usageData, id: \.serviceType) { data in
                    UsageRowView(data: data)
                }
            }
        }
        .frame(maxHeight: 280)
    }
    
    private var footerView: some View {
        HStack {
            Text("Updated: \(formattedTime(Date()))")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct UsageRowView: View {
    let data: UsageData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: data.serviceType.icon)
                    .foregroundColor(.blue)
                Text(data.serviceType.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            if let error = data.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remaining")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(data.displayRemaining)
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Used")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(data.displayUsed)
                            .font(.system(.title3, design: .monospaced))
                    }
                    
                    if data.tokenTotal != nil {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(data.displayTotal)
                                .font(.system(.title3, design: .monospaced))
                        }
                    }
                    
                    Spacer()
                }
                
                if data.tokenUsed != nil && data.tokenTotal != nil {
                    ProgressView(value: data.usagePercentage, total: 100)
                        .tint(usageColor)
                }
                
                if let refreshTime = data.refreshTime {
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Resets: \(formattedDate(refreshTime))")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding()
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

import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let usageData: [UsageData]
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), usageData: [])
    }
    
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let data = Storage.shared.loadUsageData()
        let entry = UsageEntry(date: Date(), usageData: data)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let data = Storage.shared.loadUsageData()
        let entry = UsageEntry(date: Date(), usageData: data)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct UsageWidgetEntryView: View {
    var entry: UsageProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            smallWidgetView
        case .systemMedium:
            mediumWidgetView
        case .systemLarge:
            largeWidgetView
        default:
            smallWidgetView
        }
    }
    
    private var smallWidgetView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.blue)
                Text("API Usage")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            
            Spacer()
            
            if let firstData = entry.usageData.first {
                if firstData.errorMessage != nil {
                    Text("Error")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remaining")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(firstData.displayRemaining)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.bold)
                        
                        if firstData.tokenUsed != nil && firstData.tokenTotal != nil {
                            ProgressView(value: firstData.usagePercentage, total: 100)
                                .tint(progressColor(firstData.usagePercentage))
                        }
                    }
                }
            } else {
                Text("No data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("Updated: \(formattedTime(entry.date))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private var mediumWidgetView: some View {
        HStack(spacing: 16) {
            smallWidgetView
                .frame(maxWidth: .infinity)
            
            if entry.usageData.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.usageData.dropFirst(), id: \.accountId) { data in
                        HStack {
                Image(systemName: data.provider.icon)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                Text(data.provider.displayName)
                                    .font(.caption2)
                                Text(data.displayRemaining)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
    }
    
    private var largeWidgetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                Text("API Usage Tracker")
                    .font(.headline)
                Spacer()
                Text(formattedTime(entry.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            if entry.usageData.isEmpty {
                Spacer()
                Text("No services configured")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ForEach(entry.usageData, id: \.accountId) { data in
                    largeWidgetRow(data: data)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func largeWidgetRow(data: UsageData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: data.provider.icon)
                    .foregroundColor(.blue)
                Text(data.provider.displayName)
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
                HStack(spacing: 12) {
                    StatView(title: "Remaining", value: data.displayRemaining)
                    StatView(title: "Used", value: data.displayUsed)
                    if data.tokenTotal != nil {
                        StatView(title: "Total", value: data.displayTotal)
                    }
                    Spacer()
                }
                
                if data.tokenUsed != nil && data.tokenTotal != nil {
                    ProgressView(value: data.usagePercentage, total: 100)
                        .tint(progressColor(data.usagePercentage))
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
    }
    
    private func progressColor(_ percentage: Double) -> Color {
        if percentage > 80 {
            return .red
        } else if percentage > 50 {
            return .orange
        }
        return .blue
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct StatView: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.semibold)
        }
    }
}

struct UsageWidget: Widget {
    let kind: String = "UsageWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("API Usage")
        .description("Track your API usage and quotas.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct UsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}

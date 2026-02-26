import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let usageData: [UsageData]
    let refreshIntervalMinutes: Int
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(
            date: Date(),
            usageData: WidgetUsageDataLoader.placeholderData,
            refreshIntervalMinutes: 5
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        completion(WidgetUsageDataLoader.loadEntry())
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = WidgetUsageDataLoader.loadEntry()
        let minutes = max(1, min(entry.refreshIntervalMinutes, 180))
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date().addingTimeInterval(Double(minutes) * 60)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

private enum WidgetUsageDataLoader {
    static func loadEntry() -> UsageEntry {
        let storage = Storage.shared
        let rawData = storage.loadUsageData()
        let sortedData = sort(rawData, mode: storage.loadDashboardSortMode(), manualOrder: storage.loadDashboardManualOrder())
        return UsageEntry(
            date: Date(),
            usageData: sortedData,
            refreshIntervalMinutes: storage.loadRefreshInterval()
        )
    }
    
    static func sort(_ data: [UsageData], mode: DashboardSortMode, manualOrder: [UUID]) -> [UsageData] {
        switch mode {
        case .manual:
            let orderIndex = Dictionary(uniqueKeysWithValues: manualOrder.enumerated().map { ($1, $0) })
            return data.sorted { lhs, rhs in
                let l = orderIndex[lhs.accountId] ?? Int.max
                let r = orderIndex[rhs.accountId] ?? Int.max
                if l != r { return l < r }
                return lhs.accountName.localizedCaseInsensitiveCompare(rhs.accountName) == .orderedAscending
            }
        case .risk:
            return data.sorted { lhs, rhs in
                let lRank = riskRank(for: lhs)
                let rRank = riskRank(for: rhs)
                if lRank != rRank { return lRank < rRank }
                if abs(lhs.usagePercentage - rhs.usagePercentage) > .ulpOfOne {
                    return lhs.usagePercentage > rhs.usagePercentage
                }
                if abs(lhs.monthlyUsagePercentage - rhs.monthlyUsagePercentage) > .ulpOfOne {
                    return lhs.monthlyUsagePercentage > rhs.monthlyUsagePercentage
                }
                return lhs.accountName.localizedCaseInsensitiveCompare(rhs.accountName) == .orderedAscending
            }
        case .provider:
            return data.sorted { lhs, rhs in
                if lhs.provider.displayName != rhs.provider.displayName {
                    return lhs.provider.displayName.localizedCaseInsensitiveCompare(rhs.provider.displayName) == .orderedAscending
                }
                return lhs.accountName.localizedCaseInsensitiveCompare(rhs.accountName) == .orderedAscending
            }
        case .name:
            return data.sorted {
                $0.accountName.localizedCaseInsensitiveCompare($1.accountName) == .orderedAscending
            }
        }
    }
    
    private static func riskRank(for data: UsageData) -> Int {
        if data.errorMessage != nil { return 0 }
        if data.tokenTotal != nil {
            let pct = data.usagePercentage
            if pct > 90 { return 1 }
            if pct > 70 { return 2 }
            if pct > 50 { return 3 }
            return 4
        }
        if data.monthlyTotal != nil {
            let pct = data.monthlyUsagePercentage
            if pct > 90 { return 1 }
            if pct > 70 { return 2 }
            if pct > 50 { return 3 }
            return 4
        }
        return 5
    }
    
    static var placeholderData: [UsageData] {
        let now = Date()
        return [
            UsageData(
                accountId: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
                accountName: "MiniMax 主账号",
                provider: .miniMax,
                tokenRemaining: 24500,
                tokenUsed: 75500,
                tokenTotal: 100000,
                refreshTime: Calendar.current.date(byAdding: .hour, value: 8, to: now),
                lastUpdated: now,
                errorMessage: nil,
                monthlyRemaining: nil,
                monthlyTotal: nil,
                monthlyUsed: nil,
                monthlyRefreshTime: nil,
                nextRefreshTime: nil,
                subscriptionPlan: nil
            ),
            UsageData(
                accountId: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
                accountName: "OpenAI Token",
                provider: .openAI,
                tokenRemaining: 120,
                tokenUsed: 880,
                tokenTotal: 1000,
                refreshTime: Calendar.current.date(byAdding: .day, value: 1, to: now),
                lastUpdated: now,
                errorMessage: nil,
                monthlyRemaining: nil,
                monthlyTotal: nil,
                monthlyUsed: nil,
                monthlyRefreshTime: nil,
                nextRefreshTime: nil,
                subscriptionPlan: nil
            ),
            UsageData(
                accountId: UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID(),
                accountName: "ChatGPT 订阅",
                provider: .chatGPT,
                tokenRemaining: nil,
                tokenUsed: nil,
                tokenTotal: nil,
                refreshTime: nil,
                lastUpdated: now,
                errorMessage: nil,
                monthlyRemaining: nil,
                monthlyTotal: nil,
                monthlyUsed: nil,
                monthlyRefreshTime: nil,
                nextRefreshTime: nil,
                subscriptionPlan: "plus"
            )
        ]
    }
}

struct UsageWidgetEntryView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family
    
    private var latestUpdateTime: Date {
        entry.usageData.map(\.lastUpdated).max() ?? entry.date
    }
    
    private var errorCount: Int {
        entry.usageData.filter { $0.errorMessage != nil }.count
    }
    
    private var healthyCount: Int {
        max(0, entry.usageData.count - errorCount)
    }
    
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
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader(title: "用量看板", compact: true)
            
            if let item = entry.usageData.first {
                CompactUsageCard(data: item)
            } else {
                emptyState(icon: "tray", title: "暂无数据", subtitle: "打开应用后刷新")
            }
            
            Spacer(minLength: 0)
            
            HStack(spacing: 8) {
                statusPill(text: "\(entry.usageData.count) 个账户", color: .blue)
                if errorCount > 0 {
                    statusPill(text: "\(errorCount) 异常", color: .orange)
                }
                Spacer(minLength: 0)
            }
            
            footerText
        }
        .padding(12)
    }
    
    private var mediumWidgetView: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader(title: "API 用量看板", compact: false)
            
            if entry.usageData.isEmpty {
                emptyState(icon: "chart.bar.doc.horizontal", title: "暂无用量数据", subtitle: "在菜单栏应用中配置账号并刷新")
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(entry.usageData.prefix(4)), id: \.accountId) { data in
                        WidgetUsageRow(data: data, compact: true)
                    }
                }
                Spacer(minLength: 0)
            }
            
            footerSummary
        }
        .padding(12)
    }
    
    private var largeWidgetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader(title: "API 用量看板", compact: false)
            
            if entry.usageData.isEmpty {
                emptyState(icon: "tray.full", title: "还没有可展示的账号", subtitle: "请在应用设置中添加 API 账号")
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(entry.usageData.prefix(6)), id: \.accountId) { data in
                        WidgetUsageRow(data: data, compact: false)
                    }
                }
                Spacer(minLength: 0)
            }
            
            footerSummary
        }
        .padding(14)
    }
    
    @ViewBuilder
    private func widgetHeader(title: String, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(.blue)
            Text(title)
                .font(compact ? .caption : .subheadline)
                .fontWeight(.semibold)
            Spacer(minLength: 0)
            if !entry.usageData.isEmpty {
                if errorCount > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        }
    }
    
    @ViewBuilder
    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
    
    @ViewBuilder
    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
    
    private var footerSummary: some View {
        HStack(spacing: 8) {
            statusPill(text: "正常 \(healthyCount)", color: .green)
            if errorCount > 0 {
                statusPill(text: "异常 \(errorCount)", color: .orange)
            }
            Spacer(minLength: 0)
            footerText
        }
    }
    
    private var footerText: some View {
        Text("更新于 \(WidgetFormatters.time.string(from: latestUpdateTime))")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct CompactUsageCard: View {
    let data: UsageData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: data.provider.icon)
                    .font(.caption)
                    .foregroundStyle(providerColor)
                    .frame(width: 18)
                Text(data.accountName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: 0)
                statusChip
            }
            
            if let error = data.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else {
                Text(primaryValue)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(primaryLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                if let progress = progressFraction {
                    VStack(alignment: .leading, spacing: 4) {
                        progressBar(progress: progress)
                        if let progressText {
                            Text(progressText)
                                .font(.caption2)
                                .foregroundStyle(progressColor)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    private var providerColor: Color {
        WidgetVisuals.providerColor(for: data.provider)
    }
    
    private var progressColor: Color {
        WidgetVisuals.progressColor(for: data)
    }
    
    private var statusChip: some View {
        Group {
            if data.errorMessage != nil {
                Text("异常")
                    .foregroundStyle(.orange)
            } else if let plan = data.displaySubscriptionPlan, data.provider == .chatGPT {
                Text(plan)
                    .foregroundStyle(.green)
            } else if let progressText {
                Text(progressText)
                    .foregroundStyle(progressColor)
            } else {
                Text(data.provider.displayName)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .fontWeight(.medium)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.05))
        .clipShape(Capsule())
    }
    
    private var primaryLabel: String {
        if data.tokenRemaining != nil { return "剩余额度" }
        if data.monthlyRemaining != nil { return "月度剩余" }
        if data.provider == .chatGPT, let plan = data.displaySubscriptionPlan { return "订阅计划：\(plan)" }
        return "暂无额度数值"
    }
    
    private var primaryValue: String {
        if data.tokenRemaining != nil { return data.displayRemaining }
        if data.monthlyRemaining != nil { return data.displayMonthlyRemaining }
        if let plan = data.displaySubscriptionPlan { return plan }
        return "--"
    }
    
    private var progressFraction: Double? {
        if data.tokenTotal != nil && data.tokenUsed != nil {
            return max(0, min(data.usagePercentage / 100, 1))
        }
        if data.monthlyTotal != nil && data.monthlyUsed != nil {
            return max(0, min(data.monthlyUsagePercentage / 100, 1))
        }
        return nil
    }
    
    private var progressText: String? {
        if data.tokenTotal != nil && data.tokenUsed != nil {
            return "已用 \(Int(data.usagePercentage))%"
        }
        if data.monthlyTotal != nil && data.monthlyUsed != nil {
            return "月度 \(Int(data.monthlyUsagePercentage))%"
        }
        return nil
    }
    
    @ViewBuilder
    private func progressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.18))
                Capsule()
                    .fill(progressColor)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 5)
    }
}

private struct WidgetUsageRow: View {
    let data: UsageData
    let compact: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(spacing: 8) {
                Image(systemName: data.provider.icon)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(providerColor)
                    .frame(width: compact ? 14 : 16)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(data.accountName)
                        .font(compact ? .caption : .caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(data.provider.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                if let error = data.errorMessage {
                    Label("异常", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help(error)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(primaryTrailingValue)
                            .font(.system(compact ? .caption : .footnote, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(primaryValueColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let trailingSubtitle {
                            Text(trailingSubtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            
            if data.errorMessage == nil, let progress = progressFraction {
                HStack(spacing: 6) {
                    progressBar(progress)
                    if let pct = progressText {
                        Text(pct)
                            .font(.caption2)
                            .foregroundStyle(progressColor)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 6 : 8)
        .background(Color.white.opacity(compact ? 0.35 : 0.42))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    private var providerColor: Color {
        WidgetVisuals.providerColor(for: data.provider)
    }
    
    private var progressColor: Color {
        WidgetVisuals.progressColor(for: data)
    }
    
    private var primaryValueColor: Color {
        if data.errorMessage != nil { return .orange }
        if data.tokenRemaining != nil || data.monthlyRemaining != nil { return progressColor }
        return .primary
    }
    
    private var primaryTrailingValue: String {
        if let plan = data.displaySubscriptionPlan, data.provider == .chatGPT, data.tokenRemaining == nil, data.monthlyRemaining == nil {
            return plan
        }
        if data.tokenRemaining != nil { return data.displayRemaining }
        if data.monthlyRemaining != nil { return data.displayMonthlyRemaining }
        return "--"
    }
    
    private var trailingSubtitle: String? {
        if data.tokenTotal != nil {
            return "剩余 / 总额 \(data.displayTotal)"
        }
        if data.monthlyTotal != nil {
            return "月度总额 \(data.displayMonthlyTotal)"
        }
        if data.provider == .chatGPT, let plan = data.displaySubscriptionPlan {
            return "订阅 \(plan)"
        }
        return nil
    }
    
    private var progressFraction: Double? {
        if data.tokenTotal != nil && data.tokenUsed != nil {
            return max(0, min(data.usagePercentage / 100, 1))
        }
        if data.monthlyTotal != nil && data.monthlyUsed != nil {
            return max(0, min(data.monthlyUsagePercentage / 100, 1))
        }
        return nil
    }
    
    private var progressText: String? {
        if data.tokenTotal != nil && data.tokenUsed != nil {
            return "\(Int(data.usagePercentage))%"
        }
        if data.monthlyTotal != nil && data.monthlyUsed != nil {
            return "月 \(Int(data.monthlyUsagePercentage))%"
        }
        return nil
    }
    
    @ViewBuilder
    private func progressBar(_ progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.16))
                Capsule()
                    .fill(progressColor)
                    .frame(width: max(2, geo.size.width * progress))
            }
        }
        .frame(height: 4)
    }
}

private enum WidgetVisuals {
    static func providerColor(for provider: APIProvider) -> Color {
        switch provider {
        case .miniMax:
            return Color.blue
        case .glm:
            return Color.cyan
        case .tavily:
            return Color.indigo
        case .openAI:
            return Color.green
        case .chatGPT:
            return Color.mint
        case .kimi:
            return Color.orange
        }
    }
    
    static func progressColor(for data: UsageData) -> Color {
        let percentage = data.tokenTotal != nil ? data.usagePercentage : data.monthlyUsagePercentage
        if percentage > 90 { return .red }
        if percentage > 70 { return .orange }
        if percentage > 50 { return .yellow }
        if data.errorMessage != nil { return .orange }
        return .green
    }
}

private enum WidgetFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

struct UsageWidget: Widget {
    let kind: String = "UsageWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.94, green: 0.97, blue: 1.0),
                            Color(red: 0.98, green: 0.99, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("用量看板")
        .description("在 mac 桌面查看 API 额度、剩余量和异常状态。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct UsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}

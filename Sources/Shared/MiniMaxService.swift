import Foundation

// Helper function to parse numbers from various formats
func parseNumber(_ value: Any?) -> Double? {
    guard let value = value else { return nil }
    if let d = value as? Double {
        return d
    } else if let i = value as? Int {
        return Double(i)
    } else if let s = value as? String, let d = Double(s) {
        return d
    } else if let n = value as? NSNumber {
        return n.doubleValue
    }
    return nil
}

final class Logger {
    static let shared = Logger()
    
    private var logBuffer: [String] = []
    private let bufferSize = 10
    private let flushInterval: TimeInterval = 30
    private var flushTimer: Timer?
    private let logQueue = DispatchQueue(label: "com.mactools.apiusagetracker.logger", qos: .utility)
    private let logFile: URL?
    
    private init() {
        logFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("api_tracker.log")
        startFlushTimer()
    }
    
    deinit {
        flushTimer?.invalidate()
        flushBuffer()
    }
    
    static func log(_ message: String) {
        #if DEBUG
        print("[API Tracker] \(message)")
        #endif
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        
        shared.logQueue.async {
            shared.logBuffer.append(logMessage)
            if shared.logBuffer.count >= shared.bufferSize {
                shared.flushBuffer()
            }
        }
    }
    
    private func log(_ message: String) {
        logBuffer.append(message)
        if logBuffer.count >= bufferSize {
            flushBuffer()
        }
    }
    
    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            self?.logQueue.async {
                self?.flushBuffer()
            }
        }
    }
    
    private func flushBuffer() {
        guard !logBuffer.isEmpty, let logFile = logFile else { return }
        
        let messages = logBuffer.joined(separator: "\n") + "\n"
        logBuffer.removeAll()
        
        guard let data = messages.data(using: .utf8) else { return }
        
        do {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try data.write(to: logFile)
            }
        } catch {
            print("[Logger] Failed to write to log file: \(error)")
        }
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case httpErrorWithMessage(Int, String)
    case decodingError(Error)
    case noAPIKey
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .invalidResponse:
            return "无效的响应"
        case .httpError(let code):
            return "HTTP错误: \(code)"
        case .httpErrorWithMessage(let code, let message):
            return "HTTP \(code): \(message)"
        case .decodingError:
            return "数据解析失败"
        case .noAPIKey:
            return "未配置API Key"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}

struct UsageResult {
    var remaining: Double?
    var used: Double?
    var total: Double?
    var refreshTime: Date?
    var monthlyRemaining: Double?
    var monthlyTotal: Double?
    var monthlyUsed: Double?
    var monthlyRefreshTime: Date?
    var nextRefreshTime: Date?
}

protocol UsageService {
    var provider: APIProvider { get }
    func fetchUsage(apiKey: String) async throws -> UsageResult
}

final class MiniMaxService: UsageService {
    let provider: APIProvider = .miniMax
    
    func fetchUsage(apiKey: String) async throws -> UsageResult {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        if let result = try? await fetchCodingPlanUsage(apiKey: apiKey) {
            Logger.log("MiniMax: Using Coding Plan API")
            return result
        }
        
        if let result = try? await fetchPayAsGoUsage(apiKey: apiKey) {
            Logger.log("MiniMax: Using Pay-As-You-Go API")
            return result
        }
        
        throw APIError.networkError(NSError(domain: "MiniMax", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取用量信息"]))
    }
    
    private func fetchCodingPlanUsage(apiKey: String) async throws -> UsageResult? {
        guard let url = URL(string: "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            let decoded = try JSONDecoder().decode(MiniMaxCodingResponse.self, from: data)
            
            guard let modelData = decoded.modelRemains.first else {
                return nil
            }
            
            let used = modelData.currentIntervalTotalCount - modelData.currentIntervalUsageCount
            
            Logger.log("MiniMax Coding Plan: remaining=\(modelData.currentIntervalUsageCount), used=\(used), total=\(modelData.currentIntervalTotalCount)")
            
            return UsageResult(
                remaining: Double(modelData.currentIntervalUsageCount),
                used: Double(used),
                total: Double(modelData.currentIntervalTotalCount),
                refreshTime: Date(timeIntervalSince1970: TimeInterval(modelData.endTime) / 1000)
            )
        } catch {
            Logger.log("MiniMax Coding Plan API failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func fetchPayAsGoUsage(apiKey: String) async throws -> UsageResult? {
        guard let url = URL(string: "https://api.minimax.chat/v1/billing") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = json["data"] as? [String: Any] {
                let balance = dataObj["balance"] as? Double ?? 0
                Logger.log("MiniMax Pay-As-You-Go: balance=\(balance)")
                return UsageResult(remaining: balance, used: nil, total: nil, refreshTime: nil)
            }
            
            return nil
        } catch {
            Logger.log("MiniMax Pay-As-You-Go API failed: \(error.localizedDescription)")
            return nil
        }
    }
}

struct MiniMaxCodingResponse: Codable {
    let modelRemains: [MiniMaxCodingData]
    let baseResp: BaseResp
    
    enum CodingKeys: String, CodingKey {
        case modelRemains = "model_remains"
        case baseResp = "base_resp"
    }
}

struct MiniMaxCodingData: Codable {
    let startTime: Int
    let endTime: Int
    let remainsTime: Int
    let currentIntervalTotalCount: Int
    let currentIntervalUsageCount: Int
    let modelName: String
    
    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case remainsTime = "remains_time"
        case currentIntervalTotalCount = "current_interval_total_count"
        case currentIntervalUsageCount = "current_interval_usage_count"
        case modelName = "model_name"
    }
}

struct BaseResp: Codable {
    let statusCode: Int
    let statusMsg: String
    
    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMsg = "status_msg"
    }
}

final class GLMService: UsageService {
    let provider: APIProvider = .glm
    
    func fetchUsage(apiKey: String) async throws -> UsageResult {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        let baseURL = detectBaseURL(apiKey: apiKey)
        Logger.log("GLM: Using baseURL: \(baseURL)")
        
        // Try user info API first (more reliable for balance)
        do {
            if let userInfo = try await fetchUserInfo(apiKey: apiKey, baseURL: baseURL) {
                Logger.log("GLM: Got user info response: \(userInfo)")
                
                // Try to parse wallet data
                if let wallet = userInfo["wallet"] as? [String: Any] {
                    Logger.log("GLM: Wallet data found: \(wallet)")
                    let total = parseNumber(wallet["totalQuota"]) ?? parseNumber(wallet["total_quota"]) ?? parseNumber(wallet["total"])
                    let used = parseNumber(wallet["usedQuota"]) ?? parseNumber(wallet["used_quota"]) ?? parseNumber(wallet["used"])
                    let remaining = parseNumber(wallet["remainQuota"]) ?? parseNumber(wallet["remain_quota"]) ?? parseNumber(wallet["remaining"])
                    
                    Logger.log("GLM: Parsed wallet - total=\(String(describing: total)), used=\(String(describing: used)), remaining=\(String(describing: remaining))")
                    
                    if let t = total, t > 0 {
                        let finalUsed = used ?? 0
                        let finalRemaining = remaining ?? max(0, t - finalUsed)
                        Logger.log("GLM: Using wallet data - remaining=\(finalRemaining), used=\(finalUsed), total=\(t)")
                        return UsageResult(remaining: finalRemaining, used: finalUsed, total: t, refreshTime: nil)
                    }
                }
                
                // Try alternative data structures
                if let data = userInfo["data"] as? [String: Any] {
                    if let wallet = data["wallet"] as? [String: Any] {
                        let total = parseNumber(wallet["totalQuota"]) ?? parseNumber(wallet["total"])
                        let used = parseNumber(wallet["usedQuota"]) ?? parseNumber(wallet["used"])
                        let remaining = parseNumber(wallet["remainQuota"]) ?? parseNumber(wallet["remaining"])
                        
                        if let t = total, t > 0 {
                            let finalUsed = used ?? 0
                            let finalRemaining = remaining ?? max(0, t - finalUsed)
                            Logger.log("GLM: Using data.wallet - remaining=\(finalRemaining), used=\(finalUsed), total=\(t)")
                            return UsageResult(remaining: finalRemaining, used: finalUsed, total: t, refreshTime: nil)
                        }
                    }
                }
                
                // Try quota info directly
                if let quota = userInfo["quota"] as? [String: Any] {
                    let total = parseNumber(quota["total"])
                    let used = parseNumber(quota["used"])
                    let remaining = parseNumber(quota["remaining"])
                    
                    if let t = total, t > 0 {
                        let finalUsed = used ?? 0
                        let finalRemaining = remaining ?? max(0, t - finalUsed)
                        Logger.log("GLM: Using quota - remaining=\(finalRemaining), used=\(finalUsed), total=\(t)")
                        return UsageResult(remaining: finalRemaining, used: finalUsed, total: t, refreshTime: nil)
                    }
                }
            }
        } catch {
            Logger.log("GLM: User info API failed: \(error)")
        }
        
        // Fallback to quota limit API
        Logger.log("GLM: Falling back to quota limit API")
        async let modelUsage = fetchModelUsage(apiKey: apiKey, baseURL: baseURL)
        async let quotaLimit = fetchQuotaLimit(apiKey: apiKey, baseURL: baseURL)
        
        let (modelData, quotaData) = try await (modelUsage, quotaLimit)
        
        var remaining: Double?
        var total: Double?
        var used: Double?
        var refreshTime: Date?
        
        if let quota = quotaData {
            Logger.log("GLM: Got quota data: \(quota)")
            
            // Try limits array
            if let limits = quota["limits"] as? [[String: Any]] {
                for limit in limits {
                    Logger.log("GLM: Processing limit: \(limit)")
                    if let type = limit["type"] as? String {
                        // Try various field names
                        let limitTotal = parseNumber(limit["usage"]) ?? parseNumber(limit["total"]) ?? parseNumber(limit["limit"]) ?? parseNumber(limit["max"])
                        let currentValue = parseNumber(limit["currentValue"]) ?? parseNumber(limit["current"]) ?? parseNumber(limit["used"])
                        let refreshTimestamp = parseNumber(limit["refreshTime"]) ?? parseNumber(limit["refresh_time"])
                        
                        Logger.log("GLM: Limit type=\(type), total=\(String(describing: limitTotal)), used=\(String(describing: currentValue))")
                        
                        if type == "TOKENS_LIMIT" || type == "TPM_LIMIT" || type == "QPM_LIMIT" {
                            if let lt = limitTotal {
                                total = lt
                                used = currentValue ?? 0
                                remaining = max(0, lt - used!)
                                if let rt = refreshTimestamp, rt > 0 {
                                    refreshTime = Date(timeIntervalSince1970: rt / 1000)
                                }
                                break
                            }
                        }
                    }
                }
            }
            
            // Try direct quota fields
            if total == nil || total == 0 {
                total = parseNumber(quota["total"]) ?? parseNumber(quota["totalQuota"])
                used = parseNumber(quota["used"]) ?? parseNumber(quota["usedQuota"])
                remaining = parseNumber(quota["remaining"]) ?? parseNumber(quota["remainQuota"])
                
                if let t = total, t > 0 {
                    let u = used ?? 0
                    let r = remaining ?? max(0, t - u)
                    Logger.log("GLM: Using direct quota fields - total=\(t), used=\(u), remaining=\(r)")
                    total = t
                    used = u
                    remaining = r
                }
            }
        }
        
        // If still no data, try model usage
        if used == nil || used == 0, let model = modelData {
            Logger.log("GLM: Got model usage data: \(model)")
            if let dataObj = model["data"] as? [String: Any] {
                if let totalUsage = dataObj["totalUsage"] as? [String: Any] {
                    used = parseNumber(totalUsage["totalTokensUsage"]) ?? parseNumber(totalUsage["total_tokens"])
                } else {
                    used = parseNumber(dataObj["totalUsage"]) ?? parseNumber(dataObj["total_tokens"]) ?? parseNumber(dataObj["usage"])
                }
                if let u = used {
                    Logger.log("GLM: Using model usage - used=\(u)")
                    if let t = total {
                        remaining = max(0, t - u)
                    }
                }
            }
        }
        
        Logger.log("GLM Final Result: remaining=\(String(describing: remaining)), used=\(String(describing: used)), total=\(String(describing: total)), refreshTime=\(String(describing: refreshTime))")
        return UsageResult(remaining: remaining, used: used, total: total, refreshTime: refreshTime)
    }
    
    private func fetchUserInfo(apiKey: String, baseURL: String) async throws -> [String: Any]? {
        // Try multiple possible endpoints for user info
        let possibleEndpoints = [
            "/api/user/info",
            "/api/user/balance",
            "/api/resources",
            "/api/account/info",
            "/api/user"
        ]
        
        for endpoint in possibleEndpoints {
            let urlString = "\(baseURL)\(endpoint)"
            
            guard let url = URL(string: urlString) else {
                continue
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    continue
                }
                
                Logger.log("GLM \(endpoint): HTTP \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        Logger.log("GLM \(endpoint) Response: \(json)")
                        return json
                    }
                }
            } catch {
                Logger.log("GLM \(endpoint) failed: \(error.localizedDescription)")
            }
        }
        
        return nil
    }
    
    private func detectBaseURL(apiKey: String) -> String {
        if apiKey.contains(".z.ai") || apiKey.hasPrefix("z-") {
            return "https://api.z.ai"
        }
        return "https://open.bigmodel.cn"
    }
    
    private func fetchModelUsage(apiKey: String, baseURL: String) async throws -> [String: Any]? {
        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let startTime = dateFormatter.string(from: startOfDay)
        let endTime = dateFormatter.string(from: endOfDay)
        
        let urlString = "\(baseURL)/api/monitor/usage/model-usage?startTime=\(startTime)&endTime=\(endTime)"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            Logger.log("GLM model-usage Response: \(json)")
            return json
        }
        
        return nil
    }
    
    private func fetchQuotaLimit(apiKey: String, baseURL: String) async throws -> [String: Any]? {
        let urlString = "\(baseURL)/api/monitor/usage/quota/limit"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }
        
        Logger.log("GLM quota-limit: HTTP \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            if let errorStr = String(data: data, encoding: .utf8) {
                Logger.log("GLM quota-limit Error Response: \(errorStr)")
            }
            return nil
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            Logger.log("GLM quota-limit Response: \(json)")
            return json
        }
        
        return nil
    }
}


final class TavilyService: UsageService {
    let provider: APIProvider = .tavily
    
    func fetchUsage(apiKey: String) async throws -> UsageResult {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        guard let url = URL(string: "https://api.tavily.com/usage") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            let responseString = String(data: data, encoding: .utf8) ?? "nil"
            Logger.log("Tavily API: HTTP \(httpResponse.statusCode), Response: \(responseString)")
            
            if httpResponse.statusCode != 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = json["message"] as? String ?? json["error"] as? String {
                    throw APIError.httpErrorWithMessage(httpResponse.statusCode, msg)
                }
                throw APIError.httpError(httpResponse.statusCode)
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var remaining: Double = 0
                var total: Double = 0
                var used: Double = 0
                
                if let keyObj = json["key"] as? [String: Any] {
                    if let limit = parseNumber(keyObj["limit"]), limit > 0 {
                        total = limit
                    }
                    if let usage = parseNumber(keyObj["usage"]) {
                        used = usage
                    }
                }
                
                if let accountObj = json["account"] as? [String: Any] {
                    if let planLimit = parseNumber(accountObj["plan_limit"]), planLimit > 0, total == 0 {
                        total = planLimit
                    }
                    if let planUsage = parseNumber(accountObj["plan_usage"]), used == 0 {
                        used = planUsage
                    }
                }
                
                remaining = max(0, total - used)
                
                Logger.log("Tavily API Success: remaining=\(remaining), used=\(used), total=\(total)")
                return UsageResult(remaining: remaining, used: used, total: total, refreshTime: nil)
            }
            
            throw APIError.decodingError(NSError(domain: "", code: 0))
        } catch let error as APIError {
            throw error
        } catch {
            Logger.log("Tavily API Error: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }
}

final class OpenAIService: UsageService {
    let provider: APIProvider = .openAI
    
    func fetchUsage(apiKey: String) async throws -> UsageResult {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        // OpenAI doesn't have a public usage API, so we check billing/subscription info
        guard let url = URL(string: "https://api.openai.com/v1/dashboard/billing/subscription") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            Logger.log("OpenAI API: HTTP \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 401 {
                throw APIError.httpErrorWithMessage(401, "Invalid API Key")
            }
            
            if httpResponse.statusCode != 200 {
                throw APIError.httpError(httpResponse.statusCode)
            }
            
            // Try to parse subscription info
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Logger.log("OpenAI Response: \(json)")
                
                var total: Double = 0
                var used: Double = 0
                var remaining: Double = 0
                
                // Parse hard_limit_usd (total limit)
                if let hardLimit = json["hard_limit_usd"] as? Double {
                    total = hardLimit
                }
                
                // Get usage for current month
                if let usage = try? await fetchUsageForCurrentMonth(apiKey: apiKey) {
                    used = usage
                    remaining = max(0, total - used)
                }
                
                Logger.log("OpenAI API Success: remaining=\(remaining), used=\(used), total=\(total)")
                return UsageResult(remaining: remaining, used: used, total: total, refreshTime: nil)
            }
            
            throw APIError.decodingError(NSError(domain: "", code: 0))
        } catch let error as APIError {
            throw error
        } catch {
            Logger.log("OpenAI API Error: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }
    
    private func fetchUsageForCurrentMonth(apiKey: String) async throws -> Double {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let startDate = dateFormatter.string(from: startOfMonth)
        let endDate = dateFormatter.string(from: endOfMonth)
        
        guard let url = URL(string: "https://api.openai.com/v1/dashboard/billing/usage?start_date=\(startDate)&end_date=\(endDate)") else {
            return 0
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let totalUsage = json["total_usage"] as? Double else {
                return 0
            }
            
            // Convert from cents to dollars
            return totalUsage / 100.0
        } catch {
            return 0
        }
    }
}

// MARK: - KIMI Service

final class KIMIService: UsageService {
    let provider: APIProvider = .kimi
    
    func fetchUsage(apiKey: String) async throws -> UsageResult {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        // KIMI API Base URL
        let baseURL = "https://api.moonshot.cn"
        
        // Try to fetch wallet/balance info
        let walletInfo = try? await fetchWalletInfo(apiKey: apiKey, baseURL: baseURL)
        
        var remaining: Double?
        var used: Double?
        var total: Double?
        var refreshTime: Date?
        
        if let wallet = walletInfo {
            Logger.log("KIMI: Got wallet info: \(wallet)")
            
            // Parse available balance (current quota)
            if let data = wallet["data"] as? [String: Any] {
                // Available balance (remaining)
                remaining = parseNumber(data["available_balance"]) ?? parseNumber(data["balance"])
                
                // Total vouchers (total quota granted)
                total = parseNumber(data["total_balance"]) ?? parseNumber(data["total_vouchers"])
                
                // Used amount
                used = parseNumber(data["used_balance"]) ?? parseNumber(data["consumed"])
                
                // If we have remaining and total, calculate used if not provided
                if let r = remaining, let t = total, used == nil {
                    used = max(0, t - r)
                }
                
                // Parse refresh time if available
                if let refreshAt = data["refresh_at"] as? String {
                    let formatter = ISO8601DateFormatter()
                    refreshTime = formatter.date(from: refreshAt)
                } else if let refreshTs = parseNumber(data["refresh_timestamp"]) {
                    refreshTime = Date(timeIntervalSince1970: refreshTs / 1000)
                }
            }
            
            // Try alternative response structure
            if remaining == nil && total == nil {
                if let balance = parseNumber(wallet["balance"]) {
                    remaining = balance
                }
                if let quota = parseNumber(wallet["quota"]) {
                    total = quota
                }
                if let consumed = parseNumber(wallet["consumed"]) {
                    used = consumed
                }
            }
        }
        
        // Try to fetch monthly usage stats
        if let monthlyStats = try? await fetchMonthlyStats(apiKey: apiKey, baseURL: baseURL) {
            Logger.log("KIMI: Got monthly stats: \(monthlyStats)")
            
            // Use monthly stats to supplement missing data
            if used == nil {
                used = parseNumber(monthlyStats["total_tokens"]) ?? parseNumber(monthlyStats["total_usage"])
            }
            
            // Parse monthly quota/limit
            if total == nil {
                total = parseNumber(monthlyStats["monthly_quota"]) ?? parseNumber(monthlyStats["monthly_limit"])
            }
            
            // Calculate remaining
            if let t = total, let u = used {
                remaining = max(0, t - u)
            }
            
            // Parse monthly reset time
            if refreshTime == nil {
                if let resetAt = monthlyStats["monthly_reset_at"] as? String {
                    let formatter = ISO8601DateFormatter()
                    refreshTime = formatter.date(from: resetAt)
                } else if let resetTs = parseNumber(monthlyStats["reset_timestamp"]) {
                    refreshTime = Date(timeIntervalSince1970: resetTs / 1000)
                }
            }
        }
        
        Logger.log("KIMI Final Result: remaining=\(String(describing: remaining)), used=\(String(describing: used)), total=\(String(describing: total)), refreshTime=\(String(describing: refreshTime))")
        
        return UsageResult(remaining: remaining, used: used, total: total, refreshTime: refreshTime)
    }
    
    private func fetchWalletInfo(apiKey: String, baseURL: String) async throws -> [String: Any]? {
        // Possible endpoints for wallet/balance info
        let possibleEndpoints = [
            "/v1/wallet",
            "/v1/balance",
            "/v1/user/wallet",
            "/v1/account/balance",
            "/v1/quota"
        ]
        
        for endpoint in possibleEndpoints {
            let urlString = "\(baseURL)\(endpoint)"
            
            guard let url = URL(string: urlString) else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else { continue }
                
                Logger.log("KIMI \(endpoint): HTTP \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        Logger.log("KIMI \(endpoint) Response: \(json)")
                        return json
                    }
                }
            } catch {
                Logger.log("KIMI \(endpoint) failed: \(error.localizedDescription)")
            }
        }
        
        return nil
    }
    
    private func fetchMonthlyStats(apiKey: String, baseURL: String) async throws -> [String: Any]? {
        // Get current month stats
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDate = dateFormatter.string(from: startOfMonth)
        
        // Possible endpoints for usage stats
        let possibleEndpoints = [
            "/v1/usage",
            "/v1/stats",
            "/v1/user/usage",
            "/v1/account/usage?start_date=\(startDate)",
            "/v1/billing/usage"
        ]
        
        for endpoint in possibleEndpoints {
            let urlString = "\(baseURL)\(endpoint)"
            
            guard let url = URL(string: urlString) else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else { continue }
                
                Logger.log("KIMI \(endpoint): HTTP \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        Logger.log("KIMI \(endpoint) Response: \(json)")
                        return json
                    }
                }
            } catch {
                Logger.log("KIMI \(endpoint) failed: \(error.localizedDescription)")
            }
        }
        
        return nil
    }
}

func getService(for provider: APIProvider) -> UsageService {
    switch provider {
    case .miniMax:
        return MiniMaxService()
    case .glm:
        return GLMService()
    case .tavily:
        return TavilyService()
    case .openAI:
        return OpenAIService()
    case .kimi:
        return KIMIService()
    }
}

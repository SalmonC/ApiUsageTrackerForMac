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
    var subscriptionPlan: String? = nil
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
        
        guard var components = URLComponents(string: "\(baseURL)/api/monitor/usage/model-usage") else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "startTime", value: startTime),
            URLQueryItem(name: "endTime", value: endTime)
        ]
        
        guard let url = components.url else {
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

// MARK: - ChatGPT (Web Subscription) Service

final class ChatGPTService: UsageService {
    let provider: APIProvider = .chatGPT
    
    func fetchUsage(apiKey: String) async throws -> UsageResult {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        let accessToken = try await resolveAccessToken(from: apiKey)
        let jwtClaims = decodeJWTPayload(accessToken)
        async let planInfo = fetchPlanInfo(accessToken: accessToken)
        async let limitsInfo = fetchChatRequirements(accessToken: accessToken)
        let (planJSON, limitsJSON) = await (planInfo, limitsInfo)
        
        var tokenRemaining: Double?
        var tokenUsed: Double?
        var tokenTotal: Double?
        var refreshTime: Date?
        
        var monthlyRemaining: Double?
        var monthlyUsed: Double?
        var monthlyTotal: Double?
        var monthlyRefreshTime: Date?
        var subscriptionPlan: String?
        
        var hasAnyData = false
        
        if let limitsJSON {
            Logger.log("ChatGPT limits response: \(limitsJSON)")

            var quotaCandidates: [(source: String, parsed: (remaining: Double?, used: Double?, total: Double?, resetAt: Date?, hasData: Bool))] = []

            if let messageScope = findBestQuotaContainer(in: limitsJSON, preferredKeywords: ["message", "cap"]) {
                let parsed = parseQuota(from: messageScope)
                if parsed.hasData {
                    quotaCandidates.append((source: "message", parsed: parsed))
                }
            }

            if let tokenScope = findBestQuotaContainer(in: limitsJSON, preferredKeywords: ["token"]) {
                let parsed = parseQuota(from: tokenScope)
                if parsed.hasData {
                    quotaCandidates.append((source: "token", parsed: parsed))
                }
            }

            if quotaCandidates.isEmpty {
                let parsed = parseQuota(from: limitsJSON)
                if parsed.hasData {
                    quotaCandidates.append((source: "root", parsed: parsed))
                }
            }

            let sortedCandidates = quotaCandidates.sorted { lhs, rhs in
                quotaResetPriority(lhs.parsed.resetAt) < quotaResetPriority(rhs.parsed.resetAt)
            }

            if let primary = sortedCandidates.first {
                tokenRemaining = primary.parsed.remaining
                tokenUsed = primary.parsed.used
                tokenTotal = primary.parsed.total
                refreshTime = primary.parsed.resetAt
                hasAnyData = true
            }

            if sortedCandidates.count > 1 {
                let secondary = sortedCandidates[1]
                monthlyRemaining = secondary.parsed.remaining
                monthlyUsed = secondary.parsed.used
                monthlyTotal = secondary.parsed.total
                monthlyRefreshTime = secondary.parsed.resetAt
                hasAnyData = true
            }
        }
        
        if let planJSON {
            Logger.log("ChatGPT plan response: \(planJSON)")
            let plan = parsePlanInfo(planJSON)
            if subscriptionPlan == nil {
                subscriptionPlan = plan.planType
            }
            
            if !hasAnyData, let isActive = plan.isActive {
                // Keep subscription state, but do not fabricate numeric quota values.
                if subscriptionPlan == nil {
                    subscriptionPlan = isActive ? "active" : "free"
                }
                if monthlyRefreshTime == nil {
                    monthlyRefreshTime = plan.renewalDate
                }
                hasAnyData = true
            } else if !hasAnyData, let planType = plan.planType {
                subscriptionPlan = planType
                monthlyRefreshTime = plan.renewalDate
                hasAnyData = true
            } else if monthlyRefreshTime == nil ||
                        (refreshTime != nil && datesClose(monthlyRefreshTime, refreshTime)) {
                monthlyRefreshTime = plan.renewalDate ?? monthlyRefreshTime
            }
        }
        
        // Fallback: newer tokens already embed chatgpt_plan_type in JWT claims.
        // This keeps subscription detection working even if Web internal endpoints change.
        if !hasAnyData, let jwtPlanType = parsePlanTypeFromJWTClaims(jwtClaims) {
            let normalized = jwtPlanType.lowercased()
            subscriptionPlan = normalized
            if monthlyRefreshTime == nil {
                monthlyRefreshTime = parseJWTExpiry(jwtClaims)
            }
            hasAnyData = true
            Logger.log("ChatGPT: using JWT fallback plan_type=\(normalized)")
        }
        
        guard hasAnyData else {
            throw APIError.networkError(NSError(
                domain: "ChatGPT",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "未能解析ChatGPT订阅/额度信息（accessToken 可能有效，但网页内部接口返回结构已变化）"]
            ))
        }
        
        return UsageResult(
            remaining: tokenRemaining,
            used: tokenUsed,
            total: tokenTotal,
            refreshTime: refreshTime,
            monthlyRemaining: monthlyRemaining,
            monthlyTotal: monthlyTotal,
            monthlyUsed: monthlyUsed,
            monthlyRefreshTime: monthlyRefreshTime,
            nextRefreshTime: refreshTime ?? monthlyRefreshTime,
            subscriptionPlan: subscriptionPlan
        )
    }
    
    private func resolveAccessToken(from rawInput: String) async throws -> String {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw APIError.noAPIKey }
        
        if looksLikeJWT(input) {
            return input
        }
        
        let cookieHeader = input.contains("=") ? input : "__Secure-next-auth.session-token=\(input)"
        
        for urlString in ["https://chatgpt.com/api/auth/session", "https://chat.openai.com/api/auth/session"] {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accessToken = json["accessToken"] as? String,
                   !accessToken.isEmpty {
                    Logger.log("ChatGPT: resolved accessToken via session cookie")
                    return accessToken
                }
            } catch {
                Logger.log("ChatGPT auth/session failed: \(error.localizedDescription)")
            }
        }
        
        throw APIError.networkError(NSError(
            domain: "ChatGPT",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "无法从 session cookie 换取 ChatGPT accessToken"]
        ))
    }
    
    private func fetchPlanInfo(accessToken: String) async -> [String: Any]? {
        let urls = [
            "https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27",
            "https://chatgpt.com/backend-api/accounts/check",
            "https://chat.openai.com/backend-api/accounts/check/v4-2023-04-27"
        ]
        
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            if let json = await performJSONRequest(url: url, method: "GET", accessToken: accessToken) {
                return json
            }
        }
        
        return nil
    }
    
    private func fetchChatRequirements(accessToken: String) async -> [String: Any]? {
        let urls = [
            "https://chatgpt.com/backend-api/sentinel/chat-requirements",
            "https://chat.openai.com/backend-api/sentinel/chat-requirements"
        ]
        
        let body = try? JSONSerialization.data(withJSONObject: [
            "conversation_mode_kind": "primary_assistant"
        ])
        
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            if let json = await performJSONRequest(url: url, method: "POST", accessToken: accessToken, body: body) {
                return json
            }
            if let json = await performJSONRequest(url: url, method: "GET", accessToken: accessToken) {
                return json
            }
        }
        
        return nil
    }
    
    private func performJSONRequest(url: URL, method: String, accessToken: String, body: Data? = nil) async -> [String: Any]? {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "oai-device-id")
        if let body {
            request.httpBody = body
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            Logger.log("ChatGPT \(method) \(url.path): HTTP \(http.statusCode)")
            guard (200..<300).contains(http.statusCode) else { return nil }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        } catch {
            Logger.log("ChatGPT request failed \(url.path): \(error.localizedDescription)")
        }
        
        return nil
    }
    
    private func looksLikeJWT(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        return parts.count == 3 && value.count > 40
    }
    
    private func parsePlanInfo(_ json: [String: Any]) -> (isActive: Bool?, renewalDate: Date?, planType: String?) {
        let isActive = findFirstBool(in: json, keys: [
            "is_paid_subscription_active",
            "has_active_subscription",
            "subscription_active",
            "is_active"
        ])
        
        let planType = findFirstString(in: json, keys: [
            "chatgpt_plan_type",
            "plan_type",
            "subscription_plan",
            "tier"
        ])
        
        let renewalDate =
            findFirstDate(in: json, keys: ["next_billing_date", "renewal_date", "renews_at", "expires_at"]) ??
            findFirstTimestampDate(in: json, keys: ["next_billing_date_ts", "renews_at_ts", "expires_at_ts"])
        
        return (isActive, renewalDate, planType)
    }
    
    private func findBestQuotaContainer(in json: [String: Any], preferredKeywords: [String]) -> [String: Any]? {
        var best: (score: Int, dict: [String: Any])?
        walkJSON(json) { dict in
            let lowerKeys = dict.keys.map { $0.lowercased() }
            let keywordScore = preferredKeywords.reduce(0) { partial, keyword in
                partial + lowerKeys.filter { $0.contains(keyword) }.count
            }
            let hasQuotaSignals = lowerKeys.contains(where: {
                $0.contains("remaining") || $0.contains("limit") || $0.contains("cap") || $0 == "used" || $0.contains("reset")
            })
            guard hasQuotaSignals else { return }
            let score = keywordScore + 1
            if best == nil || score > best!.score {
                best = (score, dict)
            }
        }
        return best?.dict
    }
    
    private func parseQuota(from dict: [String: Any]) -> (remaining: Double?, used: Double?, total: Double?, resetAt: Date?, hasData: Bool) {
        let remaining = findFirstNumber(in: dict, keys: [
            "remaining_tokens", "tokens_remaining", "remaining_token", "remaining",
            "remaining_messages", "messages_remaining"
        ])
        let used = findFirstNumber(in: dict, keys: [
            "used_tokens", "tokens_used", "used", "consumed", "used_messages", "messages_used"
        ])
        let total = findFirstNumber(in: dict, keys: [
            "max_tokens", "token_limit", "tokens_limit", "limit", "cap", "message_cap",
            "max_messages", "messages_limit", "total"
        ])
        let resetAt =
            findFirstDate(in: dict, keys: ["reset_at", "resets_at", "next_reset_at"]) ??
            findFirstTimestampDate(in: dict, keys: ["reset_time", "reset_ts", "reset_at_ts"])
        
        let finalUsed: Double?
        let finalRemaining: Double?
        if let total, let remaining, used == nil {
            finalUsed = max(0, total - remaining)
            finalRemaining = remaining
        } else if let total, let used, remaining == nil {
            finalUsed = used
            finalRemaining = max(0, total - used)
        } else {
            finalUsed = used
            finalRemaining = remaining
        }
        
        let hasData = finalRemaining != nil || finalUsed != nil || total != nil || resetAt != nil
        return (finalRemaining, finalUsed, total, resetAt, hasData)
    }
    
    private func walkJSON(_ value: Any, visitor: ([String: Any]) -> Void) {
        if let dict = value as? [String: Any] {
            visitor(dict)
            for child in dict.values {
                walkJSON(child, visitor: visitor)
            }
        } else if let array = value as? [Any] {
            for child in array {
                walkJSON(child, visitor: visitor)
            }
        }
    }
    
    private func findFirstNumber(in root: [String: Any], keys: [String]) -> Double? {
        let keySet = Set(keys.map { $0.lowercased() })
        var result: Double?
        walkJSON(root) { dict in
            guard result == nil else { return }
            for (key, value) in dict where keySet.contains(key.lowercased()) {
                if let parsed = parseNumber(value) {
                    result = parsed
                    return
                }
            }
        }
        return result
    }
    
    private func findFirstBool(in root: [String: Any], keys: [String]) -> Bool? {
        let keySet = Set(keys.map { $0.lowercased() })
        var result: Bool?
        walkJSON(root) { dict in
            guard result == nil else { return }
            for (key, value) in dict where keySet.contains(key.lowercased()) {
                if let boolValue = value as? Bool {
                    result = boolValue
                    return
                }
                if let numberValue = value as? NSNumber {
                    result = numberValue.boolValue
                    return
                }
                if let stringValue = value as? String {
                    let lower = stringValue.lowercased()
                    if ["true", "1", "yes", "active"].contains(lower) {
                        result = true
                        return
                    }
                    if ["false", "0", "no", "inactive"].contains(lower) {
                        result = false
                        return
                    }
                }
            }
        }
        return result
    }
    
    private func findFirstString(in root: [String: Any], keys: [String]) -> String? {
        let keySet = Set(keys.map { $0.lowercased() })
        var result: String?
        walkJSON(root) { dict in
            guard result == nil else { return }
            for (key, value) in dict where keySet.contains(key.lowercased()) {
                if let stringValue = value as? String, !stringValue.isEmpty {
                    result = stringValue
                    return
                }
            }
        }
        return result
    }
    
    private func findFirstDate(in root: [String: Any], keys: [String]) -> Date? {
        let keySet = Set(keys.map { $0.lowercased() })
        let iso = ISO8601DateFormatter()
        var result: Date?
        walkJSON(root) { dict in
            guard result == nil else { return }
            for (key, value) in dict where keySet.contains(key.lowercased()) {
                guard let stringValue = value as? String else { continue }
                if let date = iso.date(from: stringValue) {
                    result = date
                    return
                }
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                if let date = formatter.date(from: stringValue) {
                    result = date
                    return
                }
            }
        }
        return result
    }
    
    private func findFirstTimestampDate(in root: [String: Any], keys: [String]) -> Date? {
        let keySet = Set(keys.map { $0.lowercased() })
        var result: Date?
        walkJSON(root) { dict in
            guard result == nil else { return }
            for (key, value) in dict where keySet.contains(key.lowercased()) {
                guard let ts = parseNumber(value), ts > 0 else { continue }
                result = ts > 10_000_000_000 ? Date(timeIntervalSince1970: ts / 1000) : Date(timeIntervalSince1970: ts)
                return
            }
        }
        return result
    }

    private func quotaResetPriority(_ date: Date?) -> TimeInterval {
        guard let date else { return .greatestFiniteMagnitude }
        let now = Date()
        let delta = date.timeIntervalSince(now)
        if delta >= 0 {
            return delta
        }
        return abs(delta) + 86_400
    }

    private func datesClose(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return false }
        return abs(lhs.timeIntervalSince(rhs)) < 60
    }
    
    private func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
    
    private func parsePlanTypeFromJWTClaims(_ claims: [String: Any]?) -> String? {
        guard let claims else { return nil }
        
        if let auth = claims["https://api.openai.com/auth"] as? [String: Any],
           let planType = auth["chatgpt_plan_type"] as? String,
           !planType.isEmpty {
            return planType
        }
        
        return findFirstString(in: claims, keys: ["chatgpt_plan_type", "plan_type"])
    }
    
    private func parseJWTExpiry(_ claims: [String: Any]?) -> Date? {
        guard let claims else { return nil }
        if let exp = parseNumber(claims["exp"]), exp > 0 {
            return Date(timeIntervalSince1970: exp)
        }
        return nil
    }
}

// MARK: - KIMI Service

final class KIMIService: UsageService {
    let provider: APIProvider = .kimi
    
    func fetchUsage(apiKey: String) async throws -> UsageResult {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }

        var preferredAuthError: APIError?

        for endpointKind in preferredOfficialEndpoints(for: apiKey) {
            do {
                let officialResult: UsageResult?
                switch endpointKind {
                case .kimiCode:
                    officialResult = try await fetchKimiCodeUsage(apiKey: apiKey)
                case .moonshotOpenPlatform:
                    officialResult = try await fetchMoonshotOpenPlatformBalance(apiKey: apiKey)
                }

                if let officialResult, hasUsagePayload(officialResult) {
                    Logger.log("KIMI: Using official \(endpointKind.logLabel) endpoint")
                    return officialResult
                }
            } catch let error as APIError {
                if preferredAuthError == nil, isAuthError(error) {
                    preferredAuthError = error
                }
                Logger.log("KIMI official \(endpointKind.logLabel) failed: \(error.localizedDescription)")
            } catch {
                Logger.log("KIMI official \(endpointKind.logLabel) failed: \(error.localizedDescription)")
            }
        }
        
        // Legacy fallback probing (kept for compatibility)
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

        let legacyResult = UsageResult(remaining: remaining, used: used, total: total, refreshTime: refreshTime)
        if hasUsagePayload(legacyResult) {
            return legacyResult
        }

        if let preferredAuthError {
            throw preferredAuthError
        }

        throw APIError.networkError(
            NSError(
                domain: "KIMI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法获取 KIMI 用量或余额信息"]
            )
        )
    }

    private enum OfficialEndpointKind {
        case kimiCode
        case moonshotOpenPlatform

        var logLabel: String {
            switch self {
            case .kimiCode:
                return "Kimi Code"
            case .moonshotOpenPlatform:
                return "Moonshot Open Platform"
            }
        }
    }

    private func preferredOfficialEndpoints(for apiKey: String) -> [OfficialEndpointKind] {
        if isKimiCodeAPIKey(apiKey) {
            return [.kimiCode, .moonshotOpenPlatform]
        }
        return [.moonshotOpenPlatform, .kimiCode]
    }

    private func isKimiCodeAPIKey(_ apiKey: String) -> Bool {
        apiKey.hasPrefix("sk-kimi-")
    }

    private func hasUsagePayload(_ result: UsageResult) -> Bool {
        result.remaining != nil ||
        result.used != nil ||
        result.total != nil ||
        result.refreshTime != nil ||
        result.monthlyRemaining != nil ||
        result.monthlyUsed != nil ||
        result.monthlyTotal != nil ||
        result.monthlyRefreshTime != nil ||
        result.nextRefreshTime != nil ||
        result.subscriptionPlan != nil
    }

    private func isAuthError(_ error: APIError) -> Bool {
        switch error {
        case .httpError(let code):
            return code == 401 || code == 403
        case .httpErrorWithMessage(let code, _):
            return code == 401 || code == 403
        default:
            return false
        }
    }

    private func fetchKimiCodeUsage(apiKey: String) async throws -> UsageResult? {
        let json = try await fetchKIMIJSON(
            apiKey: apiKey,
            urlString: "https://api.kimi.com/coding/v1/usages"
        )
        Logger.log("KIMI Code /usages Response: \(json)")

        let user = json["user"] as? [String: Any]
        let membership = user?["membership"] as? [String: Any]
        let membershipLevel = (membership?["level"] as? String).flatMap(normalizedMembershipLevel)

        let usage = json["usage"] as? [String: Any]
        let total = parseNumber(usage?["limit"])
        var used = parseNumber(usage?["used"])
        var remaining = parseNumber(usage?["remaining"])

        if used == nil, let t = total, let r = remaining {
            used = max(0, t - r)
        }
        if remaining == nil, let t = total, let u = used {
            remaining = max(0, t - u)
        }

        let refreshTime = parseKIMIDate(usage?["resetTime"] ?? usage?["reset_time"])

        let limitSnapshots = parseKimiLimitSnapshots(from: json["limits"])
        let selectedLimitSnapshot = pickNearestUpcomingLimitSnapshot(limitSnapshots)

        let limitResetCandidates: [Date] = limitSnapshots.compactMap(\.resetAt)
        let now = Date()
        let futureCandidates = limitResetCandidates.filter { $0.timeIntervalSince(now) > -60 }
        let sortedCandidates = (futureCandidates.isEmpty ? limitResetCandidates : futureCandidates).sorted()
        let nextRefreshTime = sortedCandidates.first(where: { candidate in
            guard let refreshTime else { return true }
            return abs(candidate.timeIntervalSince(refreshTime)) > 60
        }) ?? sortedCandidates.first

        return UsageResult(
            remaining: remaining,
            used: used,
            total: total,
            refreshTime: refreshTime,
            monthlyRemaining: selectedLimitSnapshot?.remaining,
            monthlyTotal: selectedLimitSnapshot?.total,
            monthlyUsed: selectedLimitSnapshot?.used,
            monthlyRefreshTime: selectedLimitSnapshot?.resetAt,
            nextRefreshTime: selectedLimitSnapshot?.resetAt ?? nextRefreshTime,
            subscriptionPlan: membershipLevel
        )
    }

    private func fetchMoonshotOpenPlatformBalance(apiKey: String) async throws -> UsageResult? {
        let baseURLs = [
            "https://api.moonshot.cn",
            "https://api.moonshot.ai"
        ]

        var lastError: APIError?

        for baseURL in baseURLs {
            do {
                let json = try await fetchKIMIJSON(
                    apiKey: apiKey,
                    urlString: "\(baseURL)/v1/users/me/balance"
                )
                Logger.log("KIMI Moonshot /users/me/balance Response (\(baseURL)): \(json)")

                guard let data = json["data"] as? [String: Any] else {
                    continue
                }

                let available = parseNumber(data["available_balance"]) ?? parseNumber(data["balance"])
                let voucher = parseNumber(data["voucher_balance"])
                let cash = parseNumber(data["cash_balance"])

                // Open platform balance endpoint exposes remaining balance only (CNY), not token used/total.
                return UsageResult(
                    remaining: available,
                    used: nil,
                    total: nil,
                    refreshTime: nil,
                    monthlyRemaining: voucher,
                    monthlyTotal: nil,
                    monthlyUsed: nil,
                    monthlyRefreshTime: nil,
                    nextRefreshTime: nil,
                    subscriptionPlan: cash != nil ? "Open Platform" : nil
                )
            } catch let error as APIError {
                lastError = error
                // Try the alternate region host on 404/5xx/network-ish API errors.
                switch error {
                case .httpError(let code) where code == 404 || code >= 500:
                    continue
                case .httpErrorWithMessage(let code, _) where code == 404 || code >= 500:
                    continue
                default:
                    throw error
                }
            }
        }

        if let lastError {
            throw lastError
        }
        return nil
    }

    private func fetchKIMIJSON(apiKey: String, urlString: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let errorMessage =
                        ((json["error"] as? [String: Any])?["message"] as? String) ??
                        (json["message"] as? String)
                    if let errorMessage {
                        throw APIError.httpErrorWithMessage(httpResponse.statusCode, errorMessage)
                    }
                }
                throw APIError.httpError(httpResponse.statusCode)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw APIError.invalidResponse
            }
            return json
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func parseKIMIDate(_ raw: Any?) -> Date? {
        guard let raw else { return nil }
        let value: String
        if let string = raw as? String {
            value = string
        } else if let number = parseNumber(raw) {
            // Milliseconds are commonly used in some endpoints.
            if number > 10_000_000_000 {
                return Date(timeIntervalSince1970: number / 1000)
            }
            return Date(timeIntervalSince1970: number)
        } else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let basic = ISO8601DateFormatter()
        return basic.date(from: value)
    }

    private struct KimiLimitSnapshot {
        var remaining: Double?
        var used: Double?
        var total: Double?
        var resetAt: Date?

        var hasAnyData: Bool {
            remaining != nil || used != nil || total != nil || resetAt != nil
        }
    }

    private func parseKimiLimitSnapshots(from raw: Any?) -> [KimiLimitSnapshot] {
        guard let limits = raw as? [[String: Any]] else {
            return []
        }

        var snapshots: [KimiLimitSnapshot] = []
        for limit in limits {
            let detail = (limit["detail"] as? [String: Any]) ?? limit

            let total = parseNumber(detail["limit"]) ??
                parseNumber(detail["total"]) ??
                parseNumber(detail["max"]) ??
                parseNumber(detail["quota"])
            var remaining = parseNumber(detail["remaining"]) ??
                parseNumber(detail["remain"]) ??
                parseNumber(detail["available"])
            var used = parseNumber(detail["used"]) ??
                parseNumber(detail["consumed"])

            if used == nil, let total, let remaining {
                used = max(0, total - remaining)
            }
            if remaining == nil, let total, let used {
                remaining = max(0, total - used)
            }

            let resetAt =
                parseKIMIDate(detail["resetTime"] ?? detail["reset_time"] ?? detail["nextResetTime"] ?? detail["next_reset_time"]) ??
                parseKIMIDate(limit["resetTime"] ?? limit["reset_time"] ?? limit["nextResetTime"] ?? limit["next_reset_time"])

            let snapshot = KimiLimitSnapshot(
                remaining: remaining,
                used: used,
                total: total,
                resetAt: resetAt
            )

            if snapshot.hasAnyData {
                snapshots.append(snapshot)
            }
        }

        return snapshots
    }

    private func pickNearestUpcomingLimitSnapshot(_ snapshots: [KimiLimitSnapshot]) -> KimiLimitSnapshot? {
        let now = Date()
        let withReset = snapshots.filter { $0.resetAt != nil }
        let source = withReset.isEmpty ? snapshots : withReset

        return source.min { lhs, rhs in
            let lhsPriority = quotaResetPriority(lhs.resetAt, now: now)
            let rhsPriority = quotaResetPriority(rhs.resetAt, now: now)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return quotaCoverageScore(lhs) > quotaCoverageScore(rhs)
        }
    }

    private func quotaCoverageScore(_ snapshot: KimiLimitSnapshot) -> Int {
        var score = 0
        if snapshot.total != nil { score += 2 }
        if snapshot.used != nil { score += 2 }
        if snapshot.remaining != nil { score += 1 }
        return score
    }

    private func quotaResetPriority(_ date: Date?, now: Date) -> TimeInterval {
        guard let date else { return .greatestFiniteMagnitude }
        let delta = date.timeIntervalSince(now)
        if delta >= 0 {
            return delta
        }
        return abs(delta) + 86_400
    }

    private func normalizedMembershipLevel(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "LEVEL_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
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
    case .chatGPT:
        return ChatGPTService()
    case .kimi:
        return KIMIService()
    }
}

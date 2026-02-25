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

protocol UsageService {
    var provider: APIProvider { get }
    func fetchUsage(apiKey: String) async throws -> (remaining: Double?, used: Double?, total: Double?, refreshTime: Date?)
}

final class MiniMaxService: UsageService {
    let provider: APIProvider = .miniMax
    
    func fetchUsage(apiKey: String) async throws -> (remaining: Double?, used: Double?, total: Double?, refreshTime: Date?) {
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
    
    private func fetchCodingPlanUsage(apiKey: String) async throws -> (remaining: Double?, used: Double?, total: Double?, refreshTime: Date?)? {
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
            
            return (
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
    
    private func fetchPayAsGoUsage(apiKey: String) async throws -> (remaining: Double?, used: Double?, total: Double?, refreshTime: Date?)? {
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
                return (remaining: balance, used: nil, total: nil, refreshTime: nil)
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
    
    func fetchUsage(apiKey: String) async throws -> (remaining: Double?, used: Double?, total: Double?, refreshTime: Date?) {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        let baseURL = detectBaseURL(apiKey: apiKey)
        Logger.log("GLM: Using baseURL: \(baseURL)")
        
        // Try user info API first (more reliable for balance)
        if let userInfo = try? await fetchUserInfo(apiKey: apiKey, baseURL: baseURL) {
            Logger.log("GLM: Got user info")
            if let wallet = userInfo["wallet"] as? [String: Any] {
                let total = parseNumber(wallet["totalQuota"]) ?? 0
                let used = parseNumber(wallet["usedQuota"]) ?? 0
                let remaining = max(0, total - used)
                
                if total > 0 {
                    Logger.log("GLM: Using wallet data - remaining=\(remaining), used=\(used), total=\(total)")
                    return (remaining: remaining, used: used, total: total, refreshTime: nil)
                }
            }
        }
        
        // Fallback to quota limit API
        async let modelUsage = fetchModelUsage(apiKey: apiKey, baseURL: baseURL)
        async let quotaLimit = fetchQuotaLimit(apiKey: apiKey, baseURL: baseURL)
        
        let (modelData, quotaData) = try await (modelUsage, quotaLimit)
        
        var remaining: Double?
        var total: Double?
        var used: Double?
        
        if let quota = quotaData {
            Logger.log("GLM: Processing quota data")
            if let limits = quota["limits"] as? [[String: Any]] {
                for limit in limits {
                    if let type = limit["type"] as? String {
                        let limitTotal = parseNumber(limit["usage"])
                        let currentValue = parseNumber(limit["currentValue"])
                        
                        Logger.log("GLM: Limit type=\(type), total=\(String(describing: limitTotal)), used=\(String(describing: currentValue))")
                        
                        if type == "TOKENS_LIMIT" || type == "TPM_LIMIT" {
                            if let lt = limitTotal, let cv = currentValue {
                                total = lt
                                used = cv
                                remaining = max(0, lt - cv)
                                break
                            }
                        }
                    }
                }
            }
            
            // Try alternative field names
            if total == nil || total == 0 {
                if let limit = quota["limit"] as? [String: Any] {
                    total = parseNumber(limit["total"]) ?? parseNumber(limit["max"])
                    used = parseNumber(limit["used"]) ?? parseNumber(limit["current"])
                    if let t = total, let u = used {
                        remaining = max(0, t - u)
                    }
                }
            }
        }
        
        // If still no data, try model usage
        if used == nil || used == 0, let model = modelData {
            Logger.log("GLM: Processing model usage data")
            if let dataObj = model["data"] as? [String: Any] {
                used = parseNumber(dataObj["totalUsage"]) ?? parseNumber(dataObj["total_tokens"])
                if let u = used, let t = total {
                    remaining = max(0, t - u)
                }
            }
        }
        
        Logger.log("GLM API Result: remaining=\(String(describing: remaining)), used=\(String(describing: used)), total=\(String(describing: total))")
        return (remaining: remaining, used: used, total: total, refreshTime: nil)
    }
    
    private func fetchUserInfo(apiKey: String, baseURL: String) async throws -> [String: Any]? {
        let urlString = "\(baseURL)/api/user/info"
        
        guard let url = URL(string: urlString) else {
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
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Logger.log("GLM user-info Response: \(json)")
                return json
            }
            
            return nil
        } catch {
            Logger.log("GLM user-info API failed: \(error.localizedDescription)")
            return nil
        }
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
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
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
    
    func fetchUsage(apiKey: String) async throws -> (remaining: Double?, used: Double?, total: Double?, refreshTime: Date?) {
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
                return (remaining: remaining, used: used, total: total, refreshTime: nil)
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
    
    func fetchUsage(apiKey: String) async throws -> (remaining: Double?, used: Double?, total: Double?, refreshTime: Date?) {
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
                return (remaining: remaining, used: used, total: total, refreshTime: nil)
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
    }
}

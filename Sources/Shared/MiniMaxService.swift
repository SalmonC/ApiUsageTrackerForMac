import Foundation

enum Logger {
    static func log(_ message: String) {
        #if DEBUG
        print("[API Tracker] \(message)")
        #endif
        
        let logFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("api_tracker.log")
        
        if let logFile = logFile {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let logMessage = "[\(timestamp)] \(message)\n"
            
            if let data = logMessage.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logFile.path) {
                    if let handle = try? FileHandle(forWritingTo: logFile) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: logFile)
                }
            }
        }
    }
}

final class MiniMaxCodingService: UsageService {
    let serviceType: ServiceType = .miniMaxCoding
    
    func fetchUsage(apiKey: String) async throws -> UsageData {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        let urlString = "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            if httpResponse.statusCode != 200 {
                if let errorString = String(data: data, encoding: .utf8) {
                    Logger.log("MiniMax Coding API Error: HTTP \(httpResponse.statusCode), Response: \(errorString)")
                    throw APIError.httpErrorWithMessage(httpResponse.statusCode, errorString)
                }
                throw APIError.httpError(httpResponse.statusCode)
            }
            
            let decoded = try JSONDecoder().decode(MiniMaxCodingResponse.self, from: data)
            
            guard let modelData = decoded.modelRemains.first else {
                throw APIError.decodingError(NSError(domain: "", code: 0))
            }
            
            let used = modelData.currentIntervalTotalCount - modelData.currentIntervalUsageCount
            
            Logger.log("MiniMax Coding API Success: remaining=\(modelData.currentIntervalUsageCount), used=\(used), total=\(modelData.currentIntervalTotalCount)")
            
            return UsageData(
                serviceType: .miniMaxCoding,
                tokenRemaining: Double(modelData.currentIntervalUsageCount),
                tokenUsed: Double(used),
                tokenTotal: Double(modelData.currentIntervalTotalCount),
                refreshTime: Date(timeIntervalSince1970: TimeInterval(modelData.endTime) / 1000),
                lastUpdated: Date(),
                errorMessage: nil
            )
        } catch let error as APIError {
            throw error
        } catch {
            Logger.log("MiniMax Coding API Error: \(error.localizedDescription)")
            throw APIError.networkError(error)
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

final class MiniMaxPayAsGoService: UsageService {
    let serviceType: ServiceType = .miniMaxPayAsGo
    
    func fetchUsage(apiKey: String) async throws -> UsageData {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        let url = URL(string: "https://api.minimax.chat/v1/billing")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            Logger.log("MiniMax PayAsGo API Error: HTTP \(httpResponse.statusCode)")
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataObj = json["data"] as? [String: Any] {
            let balance = dataObj["balance"] as? Double ?? 0
            Logger.log("MiniMax PayAsGo API Success: balance=\(balance)")
            return UsageData(
                serviceType: .miniMaxPayAsGo,
                tokenRemaining: balance,
                tokenUsed: nil,
                tokenTotal: nil,
                refreshTime: nil,
                lastUpdated: Date(),
                errorMessage: nil
            )
        }
        
        Logger.log("MiniMax PayAsGo API Error: Failed to parse response")
        throw APIError.decodingError(NSError(domain: "", code: 0))
    }
}

final class GLMService: UsageService {
    let serviceType: ServiceType = .glm
    
    func fetchUsage(apiKey: String) async throws -> UsageData {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        let endpoints = [
            "https://open.bigmodel.cn/api/paas/v4/billing",
            "https://open.bigmodel.cn/api/paas/v4/account/info",
            "https://open.bigmodel.cn/api/paas/v3/billing"
        ]
        
        var lastError: Error?
        
        for urlString in endpoints {
            guard let url = URL(string: urlString) else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    continue
                }
                
                let responseString = String(data: data, encoding: .utf8) ?? "nil"
                Logger.log("GLM API (\(urlString)): HTTP \(httpResponse.statusCode), Response: \(responseString)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        var balance: Double = 0
                        if let b = json["balance"] as? Double {
                            balance = b
                        } else if let b = json["balance"] as? String, let d = Double(b) {
                            balance = d
                        } else if let dataObj = json["data"] as? [String: Any], let b = dataObj["balance"] as? Double {
                            balance = b
                        }
                        Logger.log("GLM API Success: balance=\(balance)")
                        return UsageData(
                            serviceType: .glm,
                            tokenRemaining: balance,
                            tokenUsed: nil,
                            tokenTotal: nil,
                            refreshTime: nil,
                            lastUpdated: Date(),
                            errorMessage: nil
                        )
                    }
                }
                
                if httpResponse.statusCode == 404 {
                    lastError = APIError.httpError(404)
                    continue
                }
            } catch {
                Logger.log("GLM API (\(urlString)) Error: \(error.localizedDescription)")
                lastError = error
            }
        }
        
        Logger.log("GLM API: All endpoints failed")
        throw APIError.httpErrorWithMessage(404, "GLM API endpoint not found. Please check your API key.")
    }
}

import Foundation

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
                    throw APIError.httpErrorWithMessage(httpResponse.statusCode, errorString)
                }
                throw APIError.httpError(httpResponse.statusCode)
            }
            
            let decoded = try JSONDecoder().decode(MiniMaxCodingResponse.self, from: data)
            
            guard let modelData = decoded.modelRemains.first else {
                throw APIError.decodingError(NSError(domain: "", code: 0))
            }
            
            let used = modelData.currentIntervalTotalCount - modelData.currentIntervalUsageCount
            
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
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataObj = json["data"] as? [String: Any] {
            let balance = dataObj["balance"] as? Double ?? 0
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
        
        throw APIError.decodingError(NSError(domain: "", code: 0))
    }
}

final class GLMService: UsageService {
    let serviceType: ServiceType = .glm
    
    func fetchUsage(apiKey: String) async throws -> UsageData {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        let url = URL(string: "https://open.bigmodel.cn/api/paas/v4/billing")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let balance = json["balance"] as? Double ?? 0
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
        
        throw APIError.decodingError(NSError(domain: "", code: 0))
    }
}

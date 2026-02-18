import Foundation

final class MiniMaxCodingService: UsageService {
    let serviceType: ServiceType = .miniMaxCoding
    
    func fetchUsage(apiKey: String) async throws -> UsageData {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        let urlString = "https://api.minimax.chat/v1/coding_plan/remains"
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
            
            if let jsonString = String(data: data, encoding: .utf8) {
                print("MiniMax API Response: \(jsonString)")
            }
            
            let decoded = try JSONDecoder().decode(MiniMaxCodingResponse.self, from: data)
            
            return UsageData(
                serviceType: .miniMaxCoding,
                tokenRemaining: Double(decoded.data.remaining),
                tokenUsed: Double(decoded.data.used),
                tokenTotal: Double(decoded.data.total),
                refreshTime: ISO8601DateFormatter().date(from: decoded.data.nextResetTime),
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
    let code: Int
    let msg: String
    let data: MiniMaxCodingData
}

struct MiniMaxCodingData: Codable {
    let remaining: Int
    let used: Int
    let total: Int
    let nextResetTime: String
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

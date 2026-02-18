import Foundation

final class MiniMaxCodingService: UsageService {
    let serviceType: ServiceType = .miniMaxCoding
    
    func fetchUsage(apiKey: String) async throws -> UsageData {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        let url = URL(string: "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains")!
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

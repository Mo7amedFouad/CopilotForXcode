import Foundation
import JSONRPC
import LanguageServerProtocol
import SuggestionModel

protocol RefactRequestType {
    associatedtype Response: Codable
    func makeURLRequest(server: String) -> URLRequest
}

extension RefactRequestType {
    func assembleURLRequest(server: String, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: .init(
            string: "\(server)/v1/\(method)"
        )!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = body
        return request
    }
}

struct RefactResponseError: Codable, Error, LocalizedError {
    var code: String
    var message: String
    var errorDescription: String? { message }
}

enum RefactRequest {
    struct GetCompletion: RefactRequestType {
        struct Response: Codable {
            let choices: [Choice]
            let model: String
            let snippetTelemetryID: Int
            
            enum CodingKeys: String, CodingKey {
                case choices
                case model
                case snippetTelemetryID = "snippet_telemetry_id"
                
            }
        }

        
        struct RequestBody: Codable {
            let noCache: Bool
            let client: String
            let parameters: Parameters
            let model: String
            let inputs: Inputs
        }

        var requestBody: RequestBody

        func makeURLRequest(server: String) -> URLRequest {
            let data = (try? JSONEncoder().encode(requestBody)) ?? Data()
            return assembleURLRequest(server: server, method: "code-completion", body: data)
        }
    }
    
    struct SnippetAccepted: RefactRequestType {
        typealias Response = Data
        
        struct RequestBody: Codable {
            let snippetTelemetryID: Int
            enum CodingKeys: String, CodingKey {
                case snippetTelemetryID = "snippet_telemetry_id"
            }
        }

        var requestBody: RequestBody
        func makeURLRequest(server: String) -> URLRequest {
            let data = (try? JSONEncoder().encode(requestBody)) ?? Data()
            return assembleURLRequest(server: server, method: "snippet-accepted", body: data)
        }
    }
}

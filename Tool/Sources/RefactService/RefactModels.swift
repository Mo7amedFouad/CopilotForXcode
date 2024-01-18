import Foundation
import JSONRPC
import LanguageServerProtocol
import SuggestionModel

// MARK: - Inputs
struct Inputs: Codable {
    let cursor: Cursor
    let sources: [String: String]
    let multiline: Bool

    enum CodingKeys: String, CodingKey {
        case cursor
        case sources
        case multiline
    }
}

struct Parameters: Codable {
    let temperature: Double
    let maxNewTokens: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case maxNewTokens
    }
}


// MARK: - Cursor
struct Cursor: Codable {
    let character: Int
    let file: String
    let line: Int

    enum CodingKeys: String, CodingKey {
        case character
        case file
        case line
    }
}

// MARK: - Choice
struct Choice: Codable {
    let codeCompletion: String
    let finishReason: String
    let index: Int

    enum CodingKeys: String, CodingKey {
        case codeCompletion = "code_completion"
        case finishReason = "finish_reason"
        case index
    }
}

import CodableWrappers
import Foundation

public struct ChatModel: Codable, Equatable {
    public var id: String
    public var name: String
    @FallbackDecoding<EmptyChatModelFormat>
    public var format: Format
    @FallbackDecoding<EmptyChatModelInfo>
    public var info: Info

    public init(id: String, name: String, format: Format, info: Info) {
        self.id = id
        self.name = name
        self.format = format
        self.info = info
    }

    public enum Format: String, Codable, Equatable {
        case openAI
        case openAIFormat
        case azureOpenAI
    }

    public struct Info: Codable, Equatable {
        @FallbackDecoding<EmptyString>
        public var apiKeyName: String
        @FallbackDecoding<EmptyString>
        public var baseURL: String
        @FallbackDecoding<EmptyInt>
        public var maxTokens: Int
        @FallbackDecoding<EmptyBool>
        public var supportsFunctionCalling: Bool
        @FallbackDecoding<EmptyString>
        public var modelName: String
        public var azureOpenAIDeploymentName: String {
            get { modelName }
            set { modelName = newValue }
        }

        public init(
            apiKeyName: String = "",
            baseURL: String = "",
            maxTokens: Int = 4000,
            supportsFunctionCalling: Bool = true,
            modelName: String = ""
        ) {
            self.apiKeyName = apiKeyName
            self.baseURL = baseURL
            self.maxTokens = maxTokens
            self.supportsFunctionCalling = supportsFunctionCalling
            self.modelName = modelName
        }
    }

    public var endpoint: String {
        switch format {
        case .openAI, .openAIFormat:
            let baseURL = info.baseURL
            if baseURL.isEmpty { return "https://api.openai.com/v1/chat/completions" }
            return "\(baseURL)/v1/chat/completions"
        case .azureOpenAI:
            let baseURL = info.baseURL
            let deployment = info.azureOpenAIDeploymentName
            let version = "2023-07-01-preview"
            if baseURL.isEmpty { return "" }
            return "\(baseURL)/openai/deployments/\(deployment)/chat/completions?api-version=\(version)"
        }
    }
}

public struct EmptyChatModelInfo: FallbackValueProvider {
    public static var defaultValue: ChatModel.Info { .init() }
}

public struct EmptyChatModelFormat: FallbackValueProvider {
    public static var defaultValue: ChatModel.Format { .openAI }
}


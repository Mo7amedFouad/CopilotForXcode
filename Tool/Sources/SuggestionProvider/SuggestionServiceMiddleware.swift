import Foundation
import Logger
import SuggestionModel

public protocol SuggestionServiceMiddleware {
    typealias Next = (SuggestionRequest) async throws -> [CodeSuggestion]

    func getSuggestion(_ request: SuggestionRequest, next: Next) async throws -> [CodeSuggestion]
}

public enum SuggestionServiceMiddlewareContainer {
    static var builtInMiddlewares: [SuggestionServiceMiddleware] = [
        DisabledLanguageSuggestionServiceMiddleware(),
    ]

    static var customMiddlewares: [SuggestionServiceMiddleware] = []

    public static var middlewares: [SuggestionServiceMiddleware] {
        builtInMiddlewares + customMiddlewares
    }

    public static func addMiddleware(_ middleware: SuggestionServiceMiddleware) {
        customMiddlewares.append(middleware)
    }
}

public struct DisabledLanguageSuggestionServiceMiddleware: SuggestionServiceMiddleware {
    public init() {}

    public func getSuggestion(
        _ request: SuggestionRequest,
        next: Next
    ) async throws -> [CodeSuggestion] {
        let language = languageIdentifierFromFileURL(request.fileURL)
        if UserDefaults.shared.value(for: \.suggestionFeatureDisabledLanguageList)
            .contains(where: { $0 == language.rawValue })
        {
            #if DEBUG
            Logger.service.info("Suggestion service is disabled for \(language).")
            #endif
            return []
        }

        return try await next(request)
    }
}

public struct DebugSuggestionServiceMiddleware: SuggestionServiceMiddleware {
    public init() {}

    public func getSuggestion(
        _ request: SuggestionRequest,
        next: Next
    ) async throws -> [CodeSuggestion] {
        Logger.service.debug("""
        Get suggestion for \(request.fileURL) at \(request.cursorPosition)
        """)
        do {
            let suggestions = try await next(request)
            Logger.service.debug("""
            Receive \(suggestions.count) suggestions for \(request.fileURL) \
            at \(request.cursorPosition)
            """)
            return suggestions
        } catch {
            Logger.service.debug("""
            Error: \(error.localizedDescription)
            """)
            throw error
        }
    }
}


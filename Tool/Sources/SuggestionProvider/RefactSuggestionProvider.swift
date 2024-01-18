import RefactService
import Foundation
import Preferences
import SuggestionModel

public actor RefactSuggestionProvider: SuggestionServiceProvider {
    let projectRootURL: URL
    let onServiceLaunched: (SuggestionServiceProvider) -> Void
    var refactService: RefactSuggestionServiceType?

    public init(
        projectRootURL: URL,
        onServiceLaunched: @escaping (SuggestionServiceProvider) -> Void
    ) {
        self.projectRootURL = projectRootURL
        self.onServiceLaunched = onServiceLaunched
    }

    func createRefactServiceIfNeeded() throws -> RefactSuggestionServiceType {
        if let refactService { return refactService }
        let newService = try RefactSuggestionService(
            projectRootURL: projectRootURL,
            onServiceLaunched: { [weak self] in
                if let self { self.onServiceLaunched(self) }
            }
        )
        refactService = newService

        return newService
    }
}

public extension RefactSuggestionProvider {
    func getSuggestions(_ request: SuggestionRequest) async throws
        -> [SuggestionModel.CodeSuggestion]
    {
        try await (createRefactServiceIfNeeded()).getCompletions(
            fileURL: request.fileURL,
            content: request.content,
            cursorPosition: request.cursorPosition,
            tabSize: request.tabSize,
            indentSize: request.indentSize,
            usesTabsForIndentation: request.usesTabsForIndentation,
            ignoreSpaceOnlySuggestions: request.ignoreSpaceOnlySuggestions
        )
    }

    func notifyAccepted(_ suggestion: SuggestionModel.CodeSuggestion) async {
        await (try? createRefactServiceIfNeeded())?.notifyAccepted(suggestion)
    }
    
    func notifyRejected(_: [SuggestionModel.CodeSuggestion]) async {}

    func notifyOpenTextDocument(fileURL: URL, content: String) async throws {
        try await (try? createRefactServiceIfNeeded())?
            .notifyOpenTextDocument(fileURL: fileURL, content: content)
    }

    func notifyChangeTextDocument(fileURL: URL, content: String) async throws {
        try await (try? createRefactServiceIfNeeded())?
            .notifyChangeTextDocument(fileURL: fileURL, content: content)
    }

    func notifyCloseTextDocument(fileURL: URL) async throws {}

    func notifySaveTextDocument(fileURL: URL) async throws {}

    func cancelRequest() async {}

    func terminate() async {
        (try? createRefactServiceIfNeeded())?.terminate()
    }
}


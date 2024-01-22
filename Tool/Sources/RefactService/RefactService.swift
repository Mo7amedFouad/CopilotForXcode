import Foundation
import LanguageClient
import LanguageServerProtocol
import Logger
import SuggestionModel
import XcodeInspector

public protocol RefactSuggestionServiceType {
    func getCompletions(
        fileURL: URL,
        content: String,
        cursorPosition: CursorPosition,
        tabSize: Int,
        indentSize: Int,
        usesTabsForIndentation: Bool,
        ignoreSpaceOnlySuggestions: Bool
    ) async throws -> [CodeSuggestion]
    func notifyAccepted(_ suggestion: CodeSuggestion) async
    func notifyOpenTextDocument(fileURL: URL, content: String) async throws
    func notifyChangeTextDocument(fileURL: URL, content: String) async throws
    func notifyCloseTextDocument(fileURL: URL) async throws
    func cancelRequest() async
    func terminate()
}

enum RefactError: Error, LocalizedError {
    case languageServerNotInstalled
    case languageServerOutdated
    case languageServiceIsInstalling

    var errorDescription: String? {
        switch self {
        case .languageServerNotInstalled:
            return "Language server is not installed. Please install it in the host app."
        case .languageServerOutdated:
            return "Language server is outdated. Please update it in the host app or update the extension."
        case .languageServiceIsInstalling:
            return "Language service is installing, please try again later."
        }
    }
}

public class RefactSuggestionService {
    static let sessionId = UUID().uuidString
    let projectRootURL: URL
    var server: RefactLSP?
    var heartbeatTask: Task<Void, Error>?
    var requestCounter: UInt64 = 0
    var cancellationCounter: UInt64 = 0
    let openedDocumentPool = OpenedDocumentPool()
    let onServiceLaunched: () -> Void
    let languageServerURL: URL
    let supportURL: URL

    private var ongoingTasks = Set<Task<[CodeSuggestion], Error>>()

    init(designatedServer: RefactLSP) {
        projectRootURL = URL(fileURLWithPath: "/")
        server = designatedServer
        onServiceLaunched = {}
        languageServerURL = URL(fileURLWithPath: "/")
        supportURL = URL(fileURLWithPath: "/")
    }

    public init(projectRootURL: URL, onServiceLaunched: @escaping () -> Void) throws {
        self.projectRootURL = projectRootURL
        self.onServiceLaunched = onServiceLaunched
        let urls = try RefactSuggestionService.createFoldersIfNeeded()
        languageServerURL = urls.executableURL.appendingPathComponent("refact-lsp")
        supportURL = urls.supportURL
        Task {
            try await setupServerIfNeeded()
        }
        
    }

    
    @discardableResult
    func setupServerIfNeeded() async throws -> RefactLSP {
        if let server { return server }

        let binaryManager = RefactInstallationManager()
        let installationStatus = binaryManager.checkInstallation()
        switch installationStatus {
        case .notInstalled:
            throw RefactError.languageServerNotInstalled
        case .installed:
            break
            
        }

        let tempFolderURL = FileManager.default.temporaryDirectory
        let managerDirectoryURL = tempFolderURL
            .appendingPathComponent("com.intii.CopilotForXcode")
            .appendingPathComponent(UUID().uuidString)
        if !FileManager.default.fileExists(atPath: managerDirectoryURL.path) {
            try FileManager.default.createDirectory(
                at: managerDirectoryURL,
                withIntermediateDirectories: true
            )
        }

        let server = RefactLanguageServer(
            languageServerExecutableURL: languageServerURL,
            managerDirectoryURL: managerDirectoryURL,
            supportURL: supportURL
        )

        server.terminationHandler = { [weak self] in
            self?.server = nil
            self?.heartbeatTask?.cancel()
            self?.requestCounter = 0
            self?.cancellationCounter = 0
            Logger.refact.info("Language server is terminated, will be restarted when needed.")
        }
    
        self.server = server
        server.start()
        return server
      
    }

    public static func createFoldersIfNeeded() throws -> (
        applicationSupportURL: URL,
        gitHubCopilotURL: URL,
        executableURL: URL,
        supportURL: URL
    ) {
        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent(
            Bundle.main
                .object(forInfoDictionaryKey: "APPLICATION_SUPPORT_FOLDER") as! String
        )

        if !FileManager.default.fileExists(atPath: supportURL.path) {
            try? FileManager.default
                .createDirectory(at: supportURL, withIntermediateDirectories: false)
        }
        let gitHubCopilotFolderURL = supportURL.appendingPathComponent("Refact")
        if !FileManager.default.fileExists(atPath: gitHubCopilotFolderURL.path) {
            try? FileManager.default
                .createDirectory(at: gitHubCopilotFolderURL, withIntermediateDirectories: false)
        }
        let supportFolderURL = gitHubCopilotFolderURL.appendingPathComponent("support")
        if !FileManager.default.fileExists(atPath: supportFolderURL.path) {
            try? FileManager.default
                .createDirectory(at: supportFolderURL, withIntermediateDirectories: false)
        }
        let executableFolderURL = gitHubCopilotFolderURL.appendingPathComponent("executable")
        if !FileManager.default.fileExists(atPath: executableFolderURL.path) {
            try? FileManager.default
                .createDirectory(at: executableFolderURL, withIntermediateDirectories: false)
        }

        return (supportURL, gitHubCopilotFolderURL, executableFolderURL, supportFolderURL)
    }
}

extension RefactSuggestionService {
    func getRelativePath(of fileURL: URL) -> String {
        let filePath = fileURL.path
        let rootPath = projectRootURL.path
        if let range = filePath.range(of: rootPath),
           range.lowerBound == filePath.startIndex
        {
            let relativePath = filePath.replacingCharacters(
                in: filePath.startIndex..<range.upperBound,
                with: ""
            )
            return relativePath
        }
        return filePath
    }
}

extension RefactSuggestionService: RefactSuggestionServiceType {
    
    public func getCompletions(
        fileURL: URL,
        content: String,
        cursorPosition: CursorPosition,
        tabSize: Int,
        indentSize: Int,
        usesTabsForIndentation: Bool,
        ignoreSpaceOnlySuggestions: Bool
    ) async throws -> [CodeSuggestion] {
        ongoingTasks.forEach { $0.cancel() }
        ongoingTasks.removeAll()

        requestCounter += 1
        let model = UserDefaults.shared.value(for: \.refactCodeCompletionModel)
        let task = Task {
            let lines = content.breakLines()
            let currentLine = lines[cursorPosition.line]
            let leftOfCursor = String(currentLine.prefix(cursorPosition.character))
            let multiline = leftOfCursor.replacingOccurrences(of: "\\s", with: "", options: .regularExpression).isEmpty
            let requestBody = RefactRequest.GetCompletion.RequestBody(
                noCache: false,
                client: "xcode",
                parameters: .init(temperature: 0.2, maxNewTokens: 50),
                model: model ,
                inputs: .init(
                    cursor: .init(
                        character: cursorPosition.character,
                        file: fileURL.path,
                        line: cursorPosition.line
                    ),
                    sources: [
                        fileURL.path:content
                    ],
                    multiline: multiline
                )
            )
            let request = RefactRequest.GetCompletion(
                requestBody: requestBody
            )
            
            try Task.checkCancellation()

            let result = try await (try await setupServerIfNeeded()).sendRequest(request)

            try Task.checkCancellation()
            

            let range0 = multiline ? CursorPosition(line: cursorPosition.line, character: 0) : cursorPosition
            let range1 = CursorPosition(line: cursorPosition.line, character: currentLine.count)
            return result.choices.enumerated().map { (index,item) in
                CodeSuggestion(
                    id: "\(result.snippetTelemetryID)",
                    text: item.codeCompletion,
                    position: cursorPosition,
                    range: .init(start: range0, end: range1)
                )
            }
        }

        ongoingTasks.insert(task)

        return try await task.value
    }

    public func cancelRequest() async {}

    public func notifyAccepted(_ suggestion: CodeSuggestion) async {
        guard let snippetTelemetryID = Int(suggestion.id) else { return }
        _ = try? await (try setupServerIfNeeded())
            .sendRequest(RefactRequest.SnippetAccepted(requestBody: .init(snippetTelemetryID: snippetTelemetryID)))
    }

    public func notifyOpenTextDocument(fileURL: URL, content: String) async throws {
        let relativePath = getRelativePath(of: fileURL)
        await openedDocumentPool.openDocument(
            url: fileURL,
            relativePath: relativePath,
            content: content
        )
    }

    public func notifyChangeTextDocument(fileURL: URL, content: String) async throws {
        let relativePath = getRelativePath(of: fileURL)
        await openedDocumentPool.updateDocument(
            url: fileURL,
            relativePath: relativePath,
            content: content
        )
    }

    public func notifyCloseTextDocument(fileURL: URL) async throws {
        await openedDocumentPool.closeDocument(url: fileURL)
    }

    public func terminate() {
        server?.terminate()
        server = nil
    }
}

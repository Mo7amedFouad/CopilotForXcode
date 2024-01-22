import Foundation
import Terminal

public struct RefactInstallationManager {
    private static var isInstalling = false

    public init() {}

    public enum InstallationStatus {
        case notInstalled
        case installed
    }

    public func checkInstallation() -> InstallationStatus {
        guard let urls = try? RefactSuggestionService.createFoldersIfNeeded()
        else { return .notInstalled }
        let executableFolderURL = urls.executableURL
        let binaryURL = executableFolderURL.appendingPathComponent("refact-lsp")

        if !FileManager.default.fileExists(atPath: binaryURL.path) {
            return .notInstalled
        } else {
            return .installed
        }
    }

    public enum InstallationStep {
        case downloading
        case uninstalling
        case decompressing
        case done
    }

    public func installLatestVersion() -> AsyncThrowingStream<InstallationStep, Error> {
        AsyncThrowingStream<InstallationStep, Error> { continuation in
            Task {
                guard !RefactInstallationManager.isInstalling else {
                    continuation.finish(throwing: RefactError.languageServiceIsInstalling)
                    return
                }
                RefactInstallationManager.isInstalling = true
                defer { RefactInstallationManager.isInstalling = false }
                do {
                    continuation.yield(.downloading)
                    let urls = try RefactSuggestionService.createFoldersIfNeeded()
                    let file = isAppleSilicon() ? "dist-aarch64-apple-darwin": "dist-x86_64-apple-darwin"
                    let urlString = "https://nightly.link/smallcloudai/refact-lsp/workflows/build/main/\(file).zip"
                    guard let url = URL(string: urlString) else { return }

                    // download
                    let (fileURL, _) = try await URLSession.shared.download(from: url)
                    let targetURL = urls.executableURL.appendingPathComponent(file).appendingPathExtension("zip")
                    try FileManager.default.copyItem(at: fileURL, to: targetURL)
                    defer { try? FileManager.default.removeItem(at: targetURL) }

                    // uninstall
                    continuation.yield(.uninstalling)
                    
                    try await uninstall()

                    // extract file
                    continuation.yield(.decompressing)
                    
                    
                    let terminal = Terminal()
                    _ = try await terminal.runCommand(
                        "/usr/bin/unzip",
                        arguments: [targetURL.path],
                        currentDirectoryURL: urls.executableURL,
                        environment: [:]
                    )
                                
                    let executableURL = targetURL.deletingLastPathComponent().appendingPathComponent("refact-lsp")
                    // update permission 755
                    try FileManager.default.setAttributes(
                        [.posixPermissions: 0o755],
                        ofItemAtPath: executableURL.path
                    )

            
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func uninstall() async throws {
        guard let urls = try? RefactSuggestionService.createFoldersIfNeeded()
        else { return }
        let executableFolderURL = urls.executableURL
        let binaryURL = executableFolderURL.appendingPathComponent("refact-lsp")
        if FileManager.default.fileExists(atPath: binaryURL.path) {
            try FileManager.default.removeItem(at: binaryURL)
        }
    }
}

func isAppleSilicon() -> Bool {
    var result = false
    #if arch(arm64)
    result = true
    #endif
    return result
}


import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
import Logger
import Preferences

protocol RefactLSP {
    func sendRequest<E: RefactRequestType>(_ endpoint: E) async throws -> E.Response
    func terminate()
}

final class RefactLanguageServer {
    let languageServerExecutableURL: URL
    let managerDirectoryURL: URL
    let supportURL: URL
    let process: Process
    let transport: IOTransport
    var terminationHandler: (() -> Void)?
    var launchHandler: (() -> Void)?
    var port: String?

    init(
        languageServerExecutableURL: URL,
        managerDirectoryURL: URL,
        supportURL: URL,
        terminationHandler: (() -> Void)? = nil,
        launchHandler: (() -> Void)? = nil
    ) {
        self.languageServerExecutableURL = languageServerExecutableURL
        self.managerDirectoryURL = managerDirectoryURL
        self.supportURL = supportURL
        self.terminationHandler = terminationHandler
        self.launchHandler = launchHandler
        process = Process()
        transport = IOTransport()

        process.standardInput = transport.stdinPipe
        process.standardOutput = transport.stdoutPipe
        process.standardError = transport.stderrPipe
        process.executableURL = languageServerExecutableURL

        let apiServerUrl = UserDefaults.shared.value(for: \.refactAddressURL)
        let apikey = UserDefaults.shared.value(for: \.refactAPIKey)
        let isVerbose = UserDefaults.shared.value(for: \.refactVerboseLog)

        let httpPort = UserDefaults.shared.value(for: \.refactHTTPPort)
        let lspPort = UserDefaults.shared.value(for: \.refactLSPPort)

        var arguments = [
            "--address-url",
            apiServerUrl,
            "--http-port",
            httpPort,
            "--lsp-port",
            lspPort
        ]
        
        if !apikey.isEmpty {
            arguments.append("--apikey")
            arguments.append(apikey)
        }
        
        if isVerbose {
            arguments.append("--logs-stderr")
        }
        

        
        process.arguments = arguments
        process.currentDirectoryURL = supportURL
        process.terminationHandler = { [weak self] task in
            self?.processTerminated(task)
        }
        
    }

    func start() {
        guard !process.isRunning else { return }
        do {
            try process.run()

            launchHandler?()
        } catch {
            Logger.refact.error(error.localizedDescription)
            processTerminated(process)
        }
    }

    deinit {
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
        }
        transport.close()
    }

    private func processTerminated(_: Process) {
        transport.close()
        terminationHandler?()
    }

    private func finishStarting() {
        Logger.refact.info("Language server started.")
        launchHandler?()
    }

    
    func terminate() {
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
        }
        transport.close()
    }
}

extension RefactLanguageServer: RefactLSP {
    func sendRequest<E>(_ request: E) async throws -> E.Response where E: RefactRequestType {
        let httpPort = UserDefaults.shared.value(for: \.refactHTTPPort)
        let request = request.makeURLRequest(server: "http://127.0.0.1:\(httpPort)")
    
        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 200 {
            do {
                let response = try JSONDecoder().decode(E.Response.self, from: data)
                return response
            } catch {
                if UserDefaults.shared.value(for: \.refactVerboseLog) {
                    dump(error)
                    Logger.refact.error(error.localizedDescription)
                }
                throw error
            }
        } else {
            do {
                let error = try JSONDecoder().decode(RefactResponseError.self, from: data)
                if error.code == "aborted" {
                    if error.message.contains("is too old") {
                        throw RefactError.languageServerOutdated
                    }
                    throw error
                }
                throw CancellationError()
            } catch {
                if UserDefaults.shared.value(for: \.refactVerboseLog) {
                    Logger.refact.error(error.localizedDescription)
                }
                throw error
            }
        }
    }
}

final class IOTransport {
    public let stdinPipe: Pipe
    public let stdoutPipe: Pipe
    public let stderrPipe: Pipe
    private var closed: Bool
    private var queue: DispatchQueue

    public init() {
        stdinPipe = Pipe()
        stdoutPipe = Pipe()
        stderrPipe = Pipe()
        closed = false
        queue = DispatchQueue(label: "com.intii.CopilotForXcode.IOTransport")

        setupFileHandleHandlers()
    }

    public func write(_ data: Data) {
        if closed {
            return
        }

        let fileHandle = stdinPipe.fileHandleForWriting

        queue.async {
            fileHandle.write(data)
        }
    }

    public func close() {
        queue.sync {
            if self.closed {
                return
            }

            self.closed = true

            [stdoutPipe, stderrPipe, stdinPipe].forEach { pipe in
                pipe.fileHandleForWriting.closeFile()
                pipe.fileHandleForReading.closeFile()
            }
        }
    }

    private func setupFileHandleHandlers() {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                return
            }

            if UserDefaults.shared.value(for: \.refactVerboseLog) {
                self?.forwardDataToHandler(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                return
            }

            if UserDefaults.shared.value(for: \.refactVerboseLog) {
                self?.forwardErrorDataToHandler(data)
            }
        }
    }

    private func forwardDataToHandler(_ data: Data) {
        queue.async { [weak self] in
            guard let self = self else { return }

            if self.closed {
                return
            }

            if let string = String(bytes: data, encoding: .utf8) {
                Logger.refact.info("stdout: \(string)")
            }
        }
    }

    private func forwardErrorDataToHandler(_ data: Data) {
        queue.async {
            if let string = String(bytes: data, encoding: .utf8) {
                Logger.refact.error("stderr: \(string)")
            }
        }
    }
}


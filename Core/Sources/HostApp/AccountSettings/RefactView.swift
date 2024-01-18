import RefactService
import Foundation
import SharedUIComponents
import SwiftUI

struct RefactView: View {
    class ViewModel: ObservableObject {
        let installationManager = RefactInstallationManager()
        @Published var installationStatus: RefactInstallationManager.InstallationStatus
        @Published var installationStep: RefactInstallationManager.InstallationStep?
        @AppStorage(\.refactVerboseLog) var refactVerboseLog
        @AppStorage(\.refactAddressURL) var refactAddressURL
        @AppStorage(\.refactAPIKey) var refactAPIKey
        @AppStorage(\.refactCodeCompletionModel) var refactCodeCompletionModel

        @AppStorage(\.refactLSPPort) var refactLSPPort
        @AppStorage(\.refactHTTPPort) var refactHTTPPort

        init() {
            installationStatus = installationManager.checkInstallation()
        }

        init(
            installationStatus: RefactInstallationManager.InstallationStatus,
            installationStep: RefactInstallationManager.InstallationStep?
        ) {
            assert(isPreview)
            self.installationStatus = installationStatus
            self.installationStep = installationStep
        }

        func refreshInstallationStatus() {
            Task { @MainActor in
                installationStatus = installationManager.checkInstallation()
            }
        }

        func install() async throws {
            defer { refreshInstallationStatus() }
            do {
                for try await step in installationManager.installLatestVersion() {
                    Task { @MainActor in
                        self.installationStep = step
                    }
                }
                Task {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    Task { @MainActor in
                        self.installationStep = nil
                    }
                }
            } catch {
                Task { @MainActor in
                    installationStep = nil
                }
                throw error
            }
        }

        func uninstall() {
            Task {
                defer { refreshInstallationStatus() }
                try await installationManager.uninstall()
            }
        }
    }

    @StateObject var viewModel = ViewModel()
    @Environment(\.toast) var toast
    @State var isSignInPanelPresented = false

    var installButton: some View {
        Button(action: {
            Task {
                do {
                    try await viewModel.install()
                } catch {
                    toast(error.localizedDescription, .error)
                }
            }
        }) {
            Text("Install")
        }
        .disabled(viewModel.installationStep != nil)
    }
    
    var uninstallButton: some View {
        Button(action: {
            viewModel.uninstall()
        }) {
            Text("Uninstall")
        }
        .disabled(viewModel.installationStep != nil)
    }

    var body: some View {
        VStack(alignment: .leading) {
            SubSection(title: Text("Refact Language Server")) {
                switch viewModel.installationStatus {
                case .notInstalled:
                    HStack {
                        Text("Language Server: Not Installed")
                        installButton
                    }
                case .installed:
                    HStack {
                        Text("Language Server: Installed")
                        uninstallButton
                    }
                }
            }
            .onChange(of: viewModel.installationStep) { newValue in
                if let step = newValue {
                    switch step {
                    case .downloading:
                        toast("Downloading..", .info)
                    case .uninstalling:
                        toast("Uninstalling old version..", .info)
                    case .decompressing:
                        toast("Decompressing..", .info)
                    case .done:
                        toast("Done!", .info)
                    }
                }
            }

            SubSection(title: Text("Configuration")) {
                Form {
                    TextField("Address URL", text: $viewModel.refactAddressURL)
                    TextField("API Key", text: $viewModel.refactAPIKey)
                    TextField("Code Completion Model", text: $viewModel.refactCodeCompletionModel)
                }
            }

            SettingsDivider("Advanced")

            Form {
                Toggle("Verbose Log", isOn: $viewModel.refactVerboseLog)
                TextField("HTTP Port", text: $viewModel.refactHTTPPort)
                TextField("LSP Port", text: $viewModel.refactLSPPort)
            }
        }
    }
}



struct RefactView_Previews: PreviewProvider {
    class TestViewModel: CodeiumView.ViewModel {
        override func generateAuthURL() -> URL {
            return URL(string: "about:blank")!
        }

        override func signIn(token: String) async throws {}

        override func signOut() async throws {}

        override func refreshInstallationStatus() {}

        override func install() async throws {}

        override func uninstall() {}
    }

    static var previews: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                CodeiumView(viewModel: TestViewModel(
                    isSignedIn: false,
                    installationStatus: .notInstalled,
                    installationStep: nil
                ))
                
                CodeiumView(viewModel: TestViewModel(
                    isSignedIn: true,
                    installationStatus: .installed("1.2.9"),
                    installationStep: nil
                ))
                
                CodeiumView(viewModel: TestViewModel(
                    isSignedIn: true,
                    installationStatus: .outdated(current: "1.2.9", latest: "1.3.0"),
                    installationStep: .downloading
                ))
                
                CodeiumView(viewModel: TestViewModel(
                    isSignedIn: true,
                    installationStatus: .unsupported(current: "1.5.9", latest: "1.3.0"),
                    installationStep: .downloading
                ))
            }
            .padding(8)
        }
    }
}


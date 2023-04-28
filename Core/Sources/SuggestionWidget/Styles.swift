import AppKit
import MarkdownUI
import SwiftUI

enum Style {
    static let panelHeight: Double = 500
    static let panelWidth: Double = 454
    static let widgetHeight: Double = 30
    static var widgetWidth: Double { widgetHeight }
    static let widgetPadding: Double = 4
}

extension Color {
    static var contentBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.isDarkMode {
                return #colorLiteral(red: 0.1580096483, green: 0.1730263829, blue: 0.2026666105, alpha: 1)
            }
            return .white
        }))
    }

    static var userChatContentBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.isDarkMode {
                return #colorLiteral(red: 0.2284317913, green: 0.2145925438, blue: 0.3214019983, alpha: 1)
            }
            return #colorLiteral(red: 0.896820749, green: 0.8709097223, blue: 0.9766687925, alpha: 1)
        }))
    }
}

extension NSAppearance {
    var isDarkMode: Bool {
        if bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return true
        } else {
            return false
        }
    }
}

extension View {
    func xcodeStyleFrame() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.3), style: .init(lineWidth: 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.2), style: .init(lineWidth: 1))
                    .padding(1)
            )
    }
}

extension MarkdownUI.Theme {
    static func custom(fontSize: Double) -> MarkdownUI.Theme {
        .gitHub.text {
            BackgroundColor(Color.clear)
            FontSize(fontSize)
        }
        .codeBlock { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.225))
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.85))
                }
                .padding(16)
                .padding(.top, 14)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .top) {
                    HStack(alignment: .center) {
                        Text(configuration.language ?? "code")
                            .foregroundStyle(.tertiary)
                            .font(.callout)
                            .padding(.leading, 8)
                            .lineLimit(1)
                        Spacer()
                        CopyButton {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(configuration.content, forType: .string)
                        }
                    }
                }
                .markdownMargin(top: 0, bottom: 16)
        }
    }
}

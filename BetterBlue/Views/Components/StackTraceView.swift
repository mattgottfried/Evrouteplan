//
//  StackTraceView.swift
//  BetterBlue
//
//  Created by Mark Schmidt on 8/25/25.
//

import BetterBlueKit
import SwiftUI

struct StackTraceView: View {
    let log: HTTPLog
    @Binding var showingRawStackTrace: Bool
    @Binding var showingShareSheet: Bool

    var demangled: String {
        guard let stackTrace = log.stackTrace else { return "No stack trace available" }

        return stackTrace.components(separatedBy: "\n")
            .enumerated()
            .map { index, line in
                let processedLine = StackTraceProcessor.processStackTraceLine(line, index: index)
                return "\(index): \(processedLine)"
            }
            .joined(separator: "\n")
    }

    var syntaxHighlightedStackTrace: AttributedString {
        guard let stackTrace = log.stackTrace else {
            return AttributedString("No stack trace available")
        }

        let processedLines = stackTrace.components(separatedBy: "\n")
            .enumerated()
            .map { index, line in
                let processedLine = StackTraceProcessor.processStackTraceLine(line, index: index)
                return "\(index): \(processedLine)"
            }

        var result = AttributedString()

        for (lineIndex, line) in processedLines.enumerated() {
            if lineIndex > 0 {
                result += AttributedString("\n")
            }

            let highlightedLine = StackTraceProcessor.applySyntaxHighlighting(to: line)
            result += highlightedLine
        }

        return result
    }

    var body: some View {
        Group {
            if showingRawStackTrace {
                Text(log.stackTrace ?? "No stack trace available")
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text(syntaxHighlightedStackTrace)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }
}

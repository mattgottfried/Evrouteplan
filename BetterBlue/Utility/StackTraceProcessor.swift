//
//  StackTraceProcessor.swift
//  BetterBlue
//
//  Created by Mark Schmidt on 8/25/25.
//

import Foundation
import SwiftUI

// Swift runtime demangling function
@_silgen_name("swift_demangle")
private func _stdlib_demangleImpl(
    mangledName: UnsafePointer<CChar>?,
    mangledNameLength: UInt,
    outputBuffer: UnsafeMutablePointer<CChar>?,
    outputBufferSize: UnsafeMutablePointer<UInt>?,
    flags: UInt32,
) -> UnsafeMutablePointer<CChar>?

enum StackTraceProcessor {
    static func processStackTraceLine(_ line: String, index _: Int) -> String {
        var cleaned = line

        // Remove frame numbers at the beginning
        cleaned = cleaned.replacingOccurrences(of: #"^\s*\d+\s+"#, with: "", options: .regularExpression)

        // Remove memory addresses
        cleaned = cleaned.replacingOccurrences(of: #"0x[0-9a-fA-F]+\s+"#, with: "", options: .regularExpression)

        // Extract framework/library name at the beginning
        var framework = ""
        if let frameworkMatch = cleaned.range(of: #"^[A-Za-z][A-Za-z0-9._-]*"#, options: .regularExpression) {
            framework = String(cleaned[frameworkMatch])
            cleaned = String(cleaned[frameworkMatch.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        // Extract the Swift mangled symbol (starts with $s)
        if let symbolRange = cleaned.range(of: #"\$s[A-Za-z0-9_]+"#, options: .regularExpression) {
            let mangledSymbol = String(cleaned[symbolRange])
            let demangledSymbol = swiftDemangle(mangledSymbol)

            // If demangling was successful and different from original, use it
            if demangledSymbol != mangledSymbol, !demangledSymbol.isEmpty {
                return "[\(framework)] \(demangledSymbol)"
            }
        }

        return processNonMangledSymbols(cleaned, framework: framework)
    }

    private static func processNonMangledSymbols(_ cleaned: String, framework: String) -> String {
        // Handle other symbols with + offset
        if let plusRange = cleaned.range(of: " + ") {
            let symbolPart = String(cleaned[..<plusRange.lowerBound])
            return "[\(framework)] \(symbolPart)"
        }

        // Handle UUID-style symbols (like from system libraries)
        if cleaned.contains("-"), cleaned.count > 30 {
            return "[\(framework)] <system>"
        }

        // Clean up and return
        let finalCleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return finalCleaned.isEmpty ? "[\(framework)] <unknown>" : "[\(framework)] \(finalCleaned)"
    }

    static func applySyntaxHighlighting(to line: String) -> AttributedString {
        var attributedString = AttributedString(line)

        // Color scheme for different elements
        let lineNumberColor = Color.secondary
        let frameworkColor = Color(.systemBlue)
        let moduleColor = Color(.systemPurple)
        let classColor = Color(.systemGreen)
        let methodColor = Color(.systemOrange)

        // Apply highlighting patterns
        applyLineNumberHighlighting(&attributedString, color: lineNumberColor)
        applyFrameworkHighlighting(&attributedString, color: frameworkColor)
        applyModuleHighlighting(&attributedString, color: moduleColor)
        applyClassHighlighting(&attributedString, color: classColor)
        applyMethodHighlighting(&attributedString, color: methodColor)

        return attributedString
    }

    private static func applyLineNumberHighlighting(_ attributedString: inout AttributedString, color: Color) {
        if let lineNumberRange = attributedString.range(of: #"^\d+:"#, options: .regularExpression) {
            attributedString[lineNumberRange].foregroundColor = color
            attributedString[lineNumberRange].font = .system(.caption, design: .monospaced)
        }
    }

    private static func applyFrameworkHighlighting(_ attributedString: inout AttributedString, color: Color) {
        if let frameworkRange = attributedString.range(of: #"\[[^\]]+\]"#, options: .regularExpression) {
            attributedString[frameworkRange].foregroundColor = color
            attributedString[frameworkRange].font = .system(.caption, design: .monospaced).weight(.semibold)
        }
    }

    private static func applyModuleHighlighting(_ attributedString: inout AttributedString, color: Color) {
        if let moduleRange = attributedString.range(of: #"\b[A-Z][a-zA-Z0-9]*\."#, options: .regularExpression) {
            attributedString[moduleRange].foregroundColor = color
        }
    }

    private static func applyClassHighlighting(_ attributedString: inout AttributedString, color: Color) {
        if let classRange = attributedString.range(of: #"\.[A-Z][a-zA-Z0-9]*\."#, options: .regularExpression) {
            attributedString[classRange].foregroundColor = color
        }
    }

    private static func applyMethodHighlighting(_ attributedString: inout AttributedString, color: Color) {
        if let methodRange = attributedString.range(of: #"\.[a-zA-Z_][a-zA-Z0-9_]*\("#, options: .regularExpression) {
            attributedString[methodRange].foregroundColor = color
        }
    }

    private static func swiftDemangle(_ symbol: String) -> String {
        symbol.withCString { symbolCString in
            guard let demangledCString = _stdlib_demangleImpl(
                mangledName: symbolCString,
                mangledNameLength: UInt(strlen(symbolCString)),
                outputBuffer: nil,
                outputBufferSize: nil,
                flags: 0,
            ) else {
                return parseManuallyIfPossible(symbol)
            }

            let demangledString = String(cString: demangledCString)
            free(demangledCString)
            return demangledString
        }
    }

    private static func parseManuallyIfPossible(_ symbol: String) -> String {
        var result = symbol

        // Remove the Swift mangling prefix
        if result.hasPrefix("$s") {
            result = String(result.dropFirst(2))
        }

        return extractModuleClassMethod(from: result) ?? symbol
    }

    private static func extractModuleClassMethod(from result: String) -> String? {
        // Try to extract module name (length-prefixed)
        guard let firstDigitIndex = result.firstIndex(where: { $0.isNumber }),
              let lengthStr = String(result[..<firstDigitIndex]).nilIfEmpty,
              let length = Int(lengthStr),
              length > 0, length < 50
        else {
            return nil
        }

        let moduleStartIndex = result.index(firstDigitIndex, offsetBy: lengthStr.count)
        guard moduleStartIndex < result.endIndex else { return nil }

        let moduleEndIndex = result.index(
            moduleStartIndex,
            offsetBy: min(length, result.distance(from: moduleStartIndex, to: result.endIndex)),
        )
        guard moduleEndIndex <= result.endIndex else { return nil }

        let moduleName = String(result[moduleStartIndex ..< moduleEndIndex])
        let remainingResult = String(result[moduleEndIndex...])

        return extractClassMethod(from: remainingResult, moduleName: moduleName)
    }

    private static func extractClassMethod(from result: String, moduleName: String) -> String? {
        // Try to extract class name
        guard let nextDigitIndex = result.firstIndex(where: { $0.isNumber }),
              let classLengthStr = String(result[..<nextDigitIndex]).nilIfEmpty,
              let classLength = Int(classLengthStr),
              classLength > 0, classLength < 50
        else {
            return "\(moduleName).<unknown>"
        }

        let classStartIndex = result.index(nextDigitIndex, offsetBy: classLengthStr.count)
        guard classStartIndex < result.endIndex else { return "\(moduleName).<unknown>" }

        let classEndIndex = result.index(
            classStartIndex,
            offsetBy: min(
                classLength,
                result.distance(from: classStartIndex, to: result.endIndex),
            ),
        )
        guard classEndIndex <= result.endIndex else { return "\(moduleName).<unknown>" }

        let className = String(result[classStartIndex ..< classEndIndex])
        let remainingResult = String(result[classEndIndex...])

        return extractMethod(from: remainingResult, moduleName: moduleName, className: className)
    }

    private static func extractMethod(from result: String, moduleName: String, className: String) -> String? {
        // Try to extract method name
        guard let methodDigitIndex = result.firstIndex(where: { $0.isNumber }),
              let methodLengthStr = String(result[..<methodDigitIndex]).nilIfEmpty,
              let methodLength = Int(methodLengthStr),
              methodLength > 0,
              methodLength < 50
        else {
            return "\(moduleName).\(className).<unknown>"
        }

        let methodStartIndex = result.index(
            methodDigitIndex,
            offsetBy: methodLengthStr.count,
        )
        guard methodStartIndex < result.endIndex else { return "\(moduleName).\(className).<unknown>" }

        let methodEndIndex = result.index(
            methodStartIndex,
            offsetBy: min(
                methodLength,
                result.distance(from: methodStartIndex, to: result.endIndex),
            ),
        )
        guard methodEndIndex <= result.endIndex else { return "\(moduleName).\(className).<unknown>" }

        let methodName = String(result[methodStartIndex ..< methodEndIndex])
        return "\(moduleName).\(className).\(methodName)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}

import Foundation

struct ParsedEntry: Identifiable, Equatable {
    let id = UUID()
    let key: String
    let value: String
    let lineNumber: Int
    let isComment: Bool
    let comment: String?
}

struct ParseError: Identifiable, Equatable {
    let id = UUID()
    let lineNumber: Int
    let message: String
}

struct ParseResult {
    let entries: [ParsedEntry]
    let errors: [ParseError]
}

enum EnvParser {
    static func parse(_ content: String) -> ParseResult {
        var entries: [ParsedEntry] = []
        var errors: [ParseError] = []
        let lines = content.components(separatedBy: .newlines)
        var lineIndex = 0

        while lineIndex < lines.count {
            let lineNumber = lineIndex + 1
            let rawLine = lines[lineIndex]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                lineIndex += 1
                continue
            }

            if trimmed.hasPrefix("#") {
                entries.append(ParsedEntry(
                    key: "",
                    value: "",
                    lineNumber: lineNumber,
                    isComment: true,
                    comment: String(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
                ))
                lineIndex += 1
                continue
            }

            var line = trimmed
            if line.hasPrefix("export ") {
                line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }

            guard let equalsIndex = line.firstIndex(of: "=") else {
                errors.append(ParseError(lineNumber: lineNumber, message: "Missing '=' separator"))
                lineIndex += 1
                continue
            }

            let key = String(line[line.startIndex..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            if key.isEmpty {
                errors.append(ParseError(lineNumber: lineNumber, message: "Empty key"))
                lineIndex += 1
                continue
            }

            var rawValue = String(line[line.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)

            if rawValue.hasPrefix("\"") {
                let (parsed, linesConsumed) = parseDoubleQuoted(rawValue: rawValue, lines: lines, startLineIndex: lineIndex)
                if let value = parsed {
                    entries.append(ParsedEntry(
                        key: key,
                        value: value,
                        lineNumber: lineNumber,
                        isComment: false,
                        comment: nil
                    ))
                    lineIndex += linesConsumed
                } else {
                    errors.append(ParseError(lineNumber: lineNumber, message: "Unterminated double quote"))
                    lineIndex += 1
                }
                continue
            }

            if rawValue.hasPrefix("'") {
                if let parsed = parseSingleQuoted(rawValue) {
                    entries.append(ParsedEntry(
                        key: key,
                        value: parsed,
                        lineNumber: lineNumber,
                        isComment: false,
                        comment: nil
                    ))
                } else {
                    errors.append(ParseError(lineNumber: lineNumber, message: "Unterminated single quote"))
                }
                lineIndex += 1
                continue
            }

            rawValue = stripInlineComment(rawValue)

            entries.append(ParsedEntry(
                key: key,
                value: rawValue,
                lineNumber: lineNumber,
                isComment: false,
                comment: nil
            ))
            lineIndex += 1
        }

        return ParseResult(entries: entries, errors: errors)
    }

    static func format(_ entries: [(key: String, value: String)]) -> String {
        entries.map { pair in
            let value = pair.value
            if value.contains("\n") || value.contains("\"") || value.contains("#") || value.contains(" ") || value.contains("$") || value.contains("`") {
                let escaped = value
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                return "\(pair.key)=\"\(escaped)\""
            }
            return "\(pair.key)=\(value)"
        }.joined(separator: "\n")
    }

    private static func parseDoubleQuoted(rawValue: String, lines: [String], startLineIndex: Int) -> (String?, Int) {
        var content = String(rawValue.dropFirst())
        var result = ""
        var lineIndex = startLineIndex
        var linesConsumed = 1

        while true {
            var i = content.startIndex
            while i < content.endIndex {
                let char = content[i]
                if char == "\\" && content.index(after: i) < content.endIndex {
                    let next = content[content.index(after: i)]
                    switch next {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    default:
                        result.append("\\")
                        result.append(next)
                    }
                    i = content.index(i, offsetBy: 2)
                } else if char == "\"" {
                    return (result, linesConsumed)
                } else {
                    result.append(char)
                    i = content.index(after: i)
                }
            }

            lineIndex += 1
            linesConsumed += 1
            if lineIndex >= lines.count {
                return (nil, linesConsumed)
            }
            result.append("\n")
            content = lines[lineIndex]
        }
    }

    private static func parseSingleQuoted(_ rawValue: String) -> String? {
        let content = String(rawValue.dropFirst())
        guard let endQuote = content.firstIndex(of: "'") else { return nil }
        return String(content[content.startIndex..<endQuote])
    }

    private static func stripInlineComment(_ value: String) -> String {
        var result = value
        if let commentRange = result.range(of: " #") {
            result = String(result[result.startIndex..<commentRange.lowerBound])
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

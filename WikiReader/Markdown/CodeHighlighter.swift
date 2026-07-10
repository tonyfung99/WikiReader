import SwiftUI

/// Minimal, language-agnostic code highlighting: line comments, quoted
/// strings, numbers, and a shared keyword set. Approximate by design — one
/// tokenizer for every fence, no per-language grammars.
nonisolated enum CodeHighlighter {
    enum TokenKind: Equatable {
        case plain, keyword, string, comment, number
    }

    struct Token: Equatable {
        let text: String
        let kind: TokenKind
    }

    private static let keywords: Set<String> = [
        "let", "var", "func", "class", "struct", "enum", "protocol", "extension",
        "if", "else", "elif", "for", "while", "return", "import", "from",
        "def", "function", "const", "public", "private", "static", "final",
        "guard", "switch", "case", "break", "continue", "default",
        "try", "catch", "except", "throw", "throws", "async", "await",
        "in", "is", "as", "not", "and", "or",
        "true", "false", "nil", "null", "None", "True", "False",
        "self", "this", "new", "type", "interface", "impl", "fn", "match",
    ]

    static func tokenize(_ code: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(code)
        var i = 0

        func flushPlain(_ buffer: inout String) {
            guard !buffer.isEmpty else { return }
            tokens.append(Token(text: buffer, kind: .plain))
            buffer = ""
        }

        var plain = ""
        while i < chars.count {
            let c = chars[i]

            // Line comments: // or #
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" || c == "#" {
                flushPlain(&plain)
                var comment = ""
                while i < chars.count && chars[i] != "\n" {
                    comment.append(chars[i])
                    i += 1
                }
                tokens.append(Token(text: comment, kind: .comment))
                continue
            }

            // Strings: "..." or '...' (with backslash escapes, single line)
            if c == "\"" || c == "'" {
                flushPlain(&plain)
                let quote = c
                var literal = String(quote)
                i += 1
                while i < chars.count && chars[i] != "\n" {
                    literal.append(chars[i])
                    if chars[i] == quote && chars[i - 1] != "\\" {
                        i += 1
                        break
                    }
                    i += 1
                }
                tokens.append(Token(text: literal, kind: .string))
                continue
            }

            // Numbers
            if c.isNumber && !(plain.last?.isLetter ?? false) {
                flushPlain(&plain)
                var number = ""
                while i < chars.count && (chars[i].isNumber || chars[i] == ".") {
                    number.append(chars[i])
                    i += 1
                }
                tokens.append(Token(text: number, kind: .number))
                continue
            }

            // Words (identifiers / keywords)
            if c.isLetter || c == "_" {
                flushPlain(&plain)
                var word = ""
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    word.append(chars[i])
                    i += 1
                }
                tokens.append(Token(text: word, kind: keywords.contains(word) ? .keyword : .plain))
                continue
            }

            plain.append(c)
            i += 1
        }
        flushPlain(&plain)
        return tokens
    }

    static func attributed(_ code: String) -> AttributedString {
        var result = AttributedString()
        for token in tokenize(code) {
            var piece = AttributedString(token.text)
            switch token.kind {
            case .plain: break
            case .keyword: piece.foregroundColor = .pink
            case .string: piece.foregroundColor = .orange
            case .comment: piece.foregroundColor = .secondary
            case .number: piece.foregroundColor = .blue
            }
            result += piece
        }
        return result
    }
}

import Foundation

/// Minimal, dependency-free block parser. Handles the markdown that clipped
/// notes actually contain: frontmatter, headings, paragraphs, lists, fenced
/// code, blockquotes, and horizontal rules. Inline spans are left to
/// `MarkdownInline`.
nonisolated enum MarkdownParser {
    static func parse(_ content: String) -> [MarkdownBlock] {
        var lines = content.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []

        if let (frontmatter, rest) = extractFrontmatter(lines) {
            blocks.append(MarkdownBlock(kind: .frontmatter(lines: frontmatter)))
            lines = rest
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let (block, next) = parseCodeFence(lines, start: index)
                blocks.append(block)
                index = next
            } else if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
            } else if isHorizontalRule(trimmed) {
                blocks.append(MarkdownBlock(kind: .rule))
                index += 1
            } else if trimmed.hasPrefix(">") {
                let (block, next) = parseQuote(lines, start: index)
                blocks.append(block)
                index = next
            } else if isBullet(trimmed) || isOrdered(trimmed) {
                let (block, next) = parseList(lines, start: index)
                blocks.append(block)
                index = next
            } else if let image = parseImage(trimmed) {
                blocks.append(image)
                index += 1
            } else if isTableStart(lines, index) {
                let (block, next) = parseTable(lines, start: index)
                blocks.append(block)
                index = next
            } else {
                let (block, next) = parseParagraph(lines, start: index)
                blocks.append(block)
                index = next
            }
        }

        return blocks
    }

    // MARK: - Frontmatter

    private static func extractFrontmatter(_ lines: [String]) -> (lines: [String], rest: [String])? {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard let closing = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else { return nil }
        let body = Array(lines[1..<closing])
        let rest = Array(lines[(closing + 1)...])
        return (body, rest)
    }

    // MARK: - Block parsers

    private static func parseHeading(_ trimmed: String) -> MarkdownBlock? {
        var level = 0
        for char in trimmed {
            if char == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let afterHashes = trimmed.dropFirst(level)
        guard afterHashes.first == " " || afterHashes.isEmpty else { return nil }
        let text = afterHashes.trimmingCharacters(in: .whitespaces)
        return MarkdownBlock(kind: .heading(level: level, text: text))
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let stripped = trimmed.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" }
            || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }

    private static func parseCodeFence(_ lines: [String], start: Int) -> (MarkdownBlock, Int) {
        let fence = lines[start].trimmingCharacters(in: .whitespaces)
        let language = String(fence.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var body: [String] = []
        var index = start + 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                index += 1
                break
            }
            body.append(lines[index])
            index += 1
        }
        let block = MarkdownBlock(kind: .code(
            language: language.isEmpty ? nil : language,
            code: body.joined(separator: "\n")
        ))
        return (block, index)
    }

    private static func parseQuote(_ lines: [String], start: Int) -> (MarkdownBlock, Int) {
        var quoted: [String] = []
        var index = start
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
            var line = lines[index].trimmingCharacters(in: .whitespaces)
            line.removeFirst()
            quoted.append(line.hasPrefix(" ") ? String(line.dropFirst()) : line)
            index += 1
        }
        if let callout = parseCallout(quoted) {
            return (callout, index)
        }
        return (MarkdownBlock(kind: .quote(lines: quoted)), index)
    }

    private static func parseCallout(_ quoted: [String]) -> MarkdownBlock? {
        guard let first = quoted.first,
              let regex = try? NSRegularExpression(pattern: "^\\[!([A-Za-z]+)\\](-?)\\s*(.*)$") else {
            return nil
        }
        let ns = first as NSString
        guard let match = regex.firstMatch(in: first, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let type = ns.substring(with: match.range(at: 1)).lowercased()
        let foldable = ns.substring(with: match.range(at: 2)) == "-"
        let title = ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
        return MarkdownBlock(kind: .callout(
            type: type,
            title: title.isEmpty ? type.capitalized : title,
            lines: Array(quoted.dropFirst()),
            foldable: foldable
        ))
    }

    private static func parseImage(_ trimmed: String) -> MarkdownBlock? {
        guard trimmed.hasPrefix("!"),
              let regex = try? NSRegularExpression(pattern: "^!\\[([^\\]]*)\\]\\(([^)]+)\\)$") else {
            return nil
        }
        let ns = trimmed as NSString
        guard let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let alt = ns.substring(with: match.range(at: 1))
        let source = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        return MarkdownBlock(kind: .image(alt: alt, source: source))
    }

    private static func parseList(_ lines: [String], start: Int) -> (MarkdownBlock, Int) {
        var items: [MarkdownListItem] = []
        var counters: [Int: Int] = [:]
        var index = start
        while index < lines.count {
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let ordered = isOrdered(trimmed)
            guard ordered || isBullet(trimmed) else { break }

            let depth = indentDepth(raw)
            for key in counters.keys where key > depth { counters[key] = nil }

            var number: Int?
            if ordered {
                let next = (counters[depth] ?? 0) + 1
                counters[depth] = next
                number = next
            } else {
                counters[depth] = nil
            }

            var text = listItemText(trimmed, ordered: ordered)
            var checked: Bool?
            if text.hasPrefix("[ ]") {
                checked = false
                text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if text.hasPrefix("[x]") || text.hasPrefix("[X]") {
                checked = true
                text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }

            items.append(MarkdownListItem(text: text, depth: depth, number: number, checked: checked))
            index += 1
        }
        return (MarkdownBlock(kind: .list(items: items)), index)
    }

    private static func indentDepth(_ raw: String) -> Int {
        var width = 0
        for char in raw {
            if char == " " { width += 1 }
            else if char == "\t" { width += 2 }
            else { break }
        }
        return width / 2
    }

    private static func parseParagraph(_ lines: [String], start: Int) -> (MarkdownBlock, Int) {
        var collected: [String] = []
        var index = start
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty
                || trimmed.hasPrefix("#")
                || trimmed.hasPrefix(">")
                || trimmed.hasPrefix("```")
                || isBullet(trimmed)
                || isOrdered(trimmed)
                || isHorizontalRule(trimmed)
                || isTableStart(lines, index)
                || parseImage(trimmed) != nil {
                break
            }
            collected.append(trimmed)
            index += 1
        }
        return (MarkdownBlock(kind: .paragraph(text: collected.joined(separator: " "))), index)
    }

    // MARK: - List helpers

    private static func isBullet(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, "-*+".contains(first) else { return false }
        let rest = trimmed.dropFirst()
        return rest.first == " "
    }

    private static func isOrdered(_ trimmed: String) -> Bool {
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty else { return false }
        let after = trimmed.dropFirst(digits.count)
        return after.first == "." && after.dropFirst().first == " "
    }

    private static func listItemText(_ trimmed: String, ordered: Bool) -> String {
        if ordered {
            let digits = trimmed.prefix { $0.isNumber }
            return trimmed.dropFirst(digits.count + 1).trimmingCharacters(in: .whitespaces)
        }
        return trimmed.dropFirst(1).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Tables

    /// A table is a header row containing a pipe, immediately followed by a
    /// delimiter row like `| --- | :--: |`.
    private static func isTableStart(_ lines: [String], _ index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        guard lines[index].contains("|") else { return false }
        return isDelimiterRow(lines[index + 1])
    }

    private static func isDelimiterRow(_ line: String) -> Bool {
        guard line.contains("-") else { return false }
        let cells = splitRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            !cell.isEmpty && cell.contains("-") && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func splitRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseTable(_ lines: [String], start: Int) -> (MarkdownBlock, Int) {
        let headers = splitRow(lines[start])
        let alignments = parseAlignments(lines[start + 1], count: headers.count)
        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains("|") else { break }
            var cells = splitRow(lines[index])
            if cells.count < headers.count {
                cells += Array(repeating: "", count: headers.count - cells.count)
            } else if cells.count > headers.count {
                cells = Array(cells.prefix(headers.count))
            }
            rows.append(cells)
            index += 1
        }
        return (MarkdownBlock(kind: .table(headers: headers, alignments: alignments, rows: rows)), index)
    }

    private static func parseAlignments(_ line: String, count: Int) -> [ColumnAlignment] {
        var result = splitRow(line).map { cell -> ColumnAlignment in
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")
            if left && right { return .center }
            if right { return .trailing }
            return .leading
        }
        if result.count < count {
            result += Array(repeating: .leading, count: count - result.count)
        }
        return Array(result.prefix(count))
    }
}

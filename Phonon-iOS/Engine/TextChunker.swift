import Foundation

/// Cleans raw pasted or imported text and splits it into paragraph-sized pieces for synthesis.
nonisolated enum TextChunker {
    /// Paragraphs longer than this are split at sentence boundaries so progress stays granular.
    static let maxChunkCharacters = 1_200

    /// Invisible code points that add nothing to speech.
    private static let invisibleScalars: Set<Unicode.Scalar> = [
        "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}", "\u{00AD}"
    ]

    /// Removes NULs and other control characters (a NUL would truncate the C string handed to the
    /// engine), normalizes line endings, and drops invisible characters.
    static func sanitize(_ text: String) -> String {
        var output = String.UnicodeScalarView()
        var previousWasCarriageReturn = false
        for scalar in text.unicodeScalars {
            defer { previousWasCarriageReturn = (scalar == "\r") }
            switch scalar {
            case "\r":
                output.append("\n")
            case "\n":
                if !previousWasCarriageReturn { output.append("\n") }
            case "\u{2028}", "\u{2029}":
                output.append("\n")
            case "\t":
                output.append(" ")
            default:
                if invisibleScalars.contains(scalar) { continue }
                if scalar.properties.generalCategory == .control { continue }
                output.append(scalar)
            }
        }
        return String(output)
    }

    /// Splits `text` into non-empty paragraphs.
    ///
    /// Blank lines separate paragraphs, and single line breaks inside a paragraph are treated as
    /// soft wraps (as in text copied from PDFs or e-mail), unless the block is a list or heading.
    /// Text without any blank lines is read one line per paragraph. Markdown markers are removed
    /// and very long paragraphs are divided at sentence boundaries.
    static func paragraphs(from text: String) -> [String] {
        let lines = sanitize(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var blocks: [[String]] = [[]]
        for line in lines {
            if line.isEmpty {
                if !(blocks.last?.isEmpty ?? true) { blocks.append([]) }
            } else {
                blocks[blocks.count - 1].append(line)
            }
        }
        blocks.removeAll { $0.isEmpty }

        let hasBlankLineSeparators = blocks.count > 1
        var result: [String] = []
        for block in blocks {
            let isStructured = block.contains { startsWithMarker($0) }
            let units: [String] = (hasBlankLineSeparators && !isStructured)
                ? [block.joined(separator: " ")]
                : block
            for unit in units {
                let line = stripMarkdownPrefix(unit).trimmingCharacters(in: .whitespaces)
                guard line.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
                if line.count <= maxChunkCharacters {
                    result.append(line)
                } else {
                    result.append(contentsOf: splitBySentences(line))
                }
            }
        }
        return result
    }

    /// Number of words, used for the duration estimate in the UI.
    static func wordCount(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    private static func startsWithMarker(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        if first == "#" || first == ">" { return true }
        return ["- ", "* ", "• "].contains { line.hasPrefix($0) }
    }

    private static func stripMarkdownPrefix(_ line: String) -> String {
        var rest = Substring(line.trimmingCharacters(in: .whitespaces))
        while let first = rest.first, first == "#" || first == ">" {
            rest = rest.dropFirst()
            rest = rest.drop(while: { $0 == " " })
        }
        for bullet in ["- ", "* ", "• "] where rest.hasPrefix(bullet) {
            rest = rest.dropFirst(bullet.count)
            break
        }
        return String(rest)
    }

    private static func splitBySentences(_ paragraph: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        paragraph.enumerateSubstrings(in: paragraph.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence else { return }
            if !current.isEmpty, current.count + sentence.count > maxChunkCharacters {
                chunks.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
            current += sentence
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { chunks.append(tail) }
        return chunks.isEmpty ? [paragraph] : chunks
    }
}

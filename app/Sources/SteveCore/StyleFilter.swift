import Foundation

/// Манера общения Стива: короткие фразы с заглавной буквы, без точки в конце, без восклицательных знаков,
/// без слов-паразитов. При включённой цензуре мат заменяется на «блин».
public struct StyleFilter {
    public var censorship: Bool

    public init(censorship: Bool = true) {
        self.censorship = censorship
    }

    /// Корни матерных слов: страховка, если мат всё же попал в ответ.
    private static let profanity = try! NSRegularExpression(
        pattern: "\\p{L}*(?:хуй|хуе|хуё|пизд|ебан|ебат|ебал|ёбан|еб[ао]нут|блят|бля|сучк|сука|суки|мудак|мудил|пидор|пидар|залуп|гондон|долбоеб|долбоёб|уеб)\\p{L}*",
        options: [.caseInsensitive]
    )

    /// Слова-паразиты в начале фразы или между запятыми.
    private static let leadingFillers = try! NSRegularExpression(
        pattern: "(?:^|(?<=[,.!?]\\s))(?:ну|короче|типа|в общем|как бы|значит|вот)\\b[,\\s]*",
        options: [.caseInsensitive]
    )
    private static let inlineFillers = try! NSRegularExpression(
        pattern: ",\\s*(?:короче|типа|как бы|значит|в общем)\\s*,",
        options: [.caseInsensitive]
    )
    private static let sentenceStart = try! NSRegularExpression(pattern: "([.?]\\s+)(\\p{Ll})")

    public func finalize(_ text: String) -> String {
        polish(censor(text))
    }

    func censor(_ text: String) -> String {
        guard censorship else { return text }
        return Self.profanity.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "блин")
    }

    func polish(_ input: String) -> String {
        var text = replace(Self.inlineFillers, in: input, with: ",")
        text = replace(Self.leadingFillers, in: text, with: "").trimmingCharacters(in: .whitespaces)
        text = text.replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "—", with: "–") // длинное тире заменяется на короткое, короткое остаётся как есть
        if text.hasSuffix(".") { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespaces)
        guard let first = text.first else { return text }
        text = first.uppercased() + text.dropFirst()
        return uppercaseSentenceStarts(in: text)
    }

    private func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private func uppercaseSentenceStarts(in text: String) -> String {
        var result = text
        let matches = Self.sentenceStart.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 2), in: result) else { continue }
            result.replaceSubrange(range, with: result[range].uppercased())
        }
        return result
    }
}

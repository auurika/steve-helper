import Foundation

/// Готовит текст к озвучке: синтезатор не должен читать кавычки, скобки, значки разметки и эмодзи.
public enum SpeechText {
    public static func clean(_ text: String) -> String {
        var result = text
        // эмодзи и пиктограммы
        result = result.unicodeScalars.filter { !$0.properties.isEmojiPresentation && !($0.properties.isEmoji && $0.value > 0x2000) }
            .map(String.init).joined()
        // кавычки всех видов
        result = result.replacingOccurrences(of: "[«»“”„‟\"`]", with: "", options: .regularExpression)
        // апострофы вне слов («it's» остаётся целым)
        result = result.replacingOccurrences(of: "(?<!\\p{L})['‘’]|['‘’](?!\\p{L})", with: "", options: .regularExpression)
        // значки разметки и скобки
        result = result.replacingOccurrences(of: "[*_#~|\\\\^<>\\[\\]{}()]", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "[→←↑↓•·]", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "…", with: ",")
        result = result.replacingOccurrences(of: "\\s+[—–]\\s+", with: ", ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s+([.,!?:;])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

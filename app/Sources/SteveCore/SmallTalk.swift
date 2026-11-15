import Foundation

/// Простые ответы без модели: приветствия, благодарности и «не понял».
/// Живой разговор на произвольные темы — задача языковой модели (см. ChatEngine в приложении).
public struct SmallTalk {
    private let greetings: [String]
    private let thanks: [String]
    private let unknown: [String]

    /// `profanity` включает редкие матерные реплики. Это то же, что выключенная цензура в настройках.
    public init(profanity: Bool = false) {
        greetings = ["Здарова", "Привет", "Привет, я тут", "О, привет", "Ну привет", "Я здесь, говори"] + (profanity ? ["Здарова, бля", "Ну здарова, чё как"] : [])
        thanks = ["Да не за что", "Обращайся", "Ага, стараюсь", "Всегда рад", "Заходи ещё", "Пустяки"] + (profanity ? ["Да не за что, бля", "Обращайся, хуле"] : [])
        unknown = [
            "Пока не умею такое",
            "Не понял, скажи по-другому",
            "Это пока не по моей части",
            "Такого я ещё не умею",
            "Не уловил, повтори иначе",
            "Тут я пока бессилен",
        ] + (profanity ? ["Нихуя не понял, повтори", "Хуй пойми, скажи по-другому"] : [])
    }

    public func greeting(hour: Int = Calendar.current.component(.hour, from: Date()),
                         pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        let morning = ["Доброе утро", "Утро доброе", "С добрым утром"]
        let night = ["Не спится?", "Чего не спишь?", "Поздновато, а ты тут"]
        switch hour {
        case 5..<12: return morning[pick(morning.count)]
        case 22..<24, 0..<5: return night[pick(night.count)]
        default: return greetings[pick(greetings.count)]
        }
    }

    public func thanksReply(pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        thanks[pick(thanks.count)]
    }

    public func unknownReply(pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        unknown[pick(unknown.count)]
    }
}

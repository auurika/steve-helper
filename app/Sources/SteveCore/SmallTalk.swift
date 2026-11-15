import Foundation

/// Простые ответы без модели: приветствия, благодарности и «не понял».
/// Живой разговор на произвольные темы — задача языковой модели (см. ChatEngine в приложении).
public struct SmallTalk {
    private let greetings = ["Здарова", "Привет", "Привет, я тут"]
    private let thanks = ["Да не за что", "Обращайся", "Ага, стараюсь"]
    private let unknown = [
        "Пока не умею такое",
        "Не понял, скажи по-другому",
        "Это пока не по моей части",
    ]

    public init() {}

    public func greeting(hour: Int = Calendar.current.component(.hour, from: Date()),
                         pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        switch hour {
        case 5..<12: return "Доброе утро"
        case 22..<24, 0..<5: return "Не спится?"
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

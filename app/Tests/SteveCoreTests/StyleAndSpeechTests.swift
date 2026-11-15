import XCTest
@testable import SteveCore

final class StyleFilterTests: XCTestCase {
    func testStartsWithCapitalAndDropsTrailingPeriodAndExclamation() {
        let filter = StyleFilter()
        XCTAssertEqual(filter.finalize("привет! как дела?"), "Привет как дела?")
        XCTAssertEqual(filter.finalize("Событие добавлено."), "Событие добавлено")
    }

    func testRemovesFillerWords() {
        let filter = StyleFilter()
        XCTAssertEqual(filter.finalize("ну, понял. ставлю таймер."), "Понял. Ставлю таймер")
        XCTAssertEqual(filter.finalize("Короче, открываю Safari."), "Открываю Safari")
    }

    func testCapitalizesEachSentence() {
        XCTAssertEqual(StyleFilter().finalize("понял. ставлю таймер"), "Понял. Ставлю таймер")
    }

    func testCensorshipReplacesProfanity() {
        XCTAssertEqual(StyleFilter(censorship: true).finalize("Да это пиздец, блять"), "Да это блин, блин")
    }

    func testProfanityStaysWhenCensorshipIsOff() {
        XCTAssertEqual(StyleFilter(censorship: false).finalize("Да это пиздец"), "Да это пиздец")
    }
}

final class SpeechTextTests: XCTestCase {
    func testQuotesAndMarkupAreNotSpoken() {
        let spoken = SpeechText.clean("Открываю «Safari»: громкость 30% — готово… (ок) *жирный* \"цитата\" it's fine 🙂")
        XCTAssertEqual(spoken, "Открываю Safari: громкость 30%, готово, ок жирный цитата it's fine")
    }

    func testPlainTextStaysUntouched() {
        XCTAssertEqual(SpeechText.clean("Таймер на 10 минут"), "Таймер на 10 минут")
    }
}

final class PitchEstimatorTests: XCTestCase {
    private func tone(_ hertz: Double, seconds: Double = 1.5, sampleRate: Double = 44100) -> [Float] {
        (0..<Int(sampleRate * seconds)).map { i in
            let t = Double(i) / sampleRate
            return Float((sin(2 * .pi * hertz * t) + 0.4 * sin(2 * .pi * 2 * hertz * t)) * 0.35)
        }
    }

    func testFindsHighAndLowPitchWithoutOctaveError() throws {
        let high = try XCTUnwrap(PitchEstimator.estimate(samples: tone(220), sampleRate: 44100))
        let low = try XCTUnwrap(PitchEstimator.estimate(samples: tone(120), sampleRate: 44100))
        XCTAssertEqual(high, 220, accuracy: 6)
        XCTAssertEqual(low, 120, accuracy: 4)
    }

    func testSilenceHasNoPitch() {
        XCTAssertNil(PitchEstimator.estimate(samples: [Float](repeating: 0, count: 44100), sampleRate: 44100))
    }

    func testMultiplierIsClamped() {
        XCTAssertEqual(PitchEstimator.pitchMultiplier(forHz: 150), 1, accuracy: 0.001)
        XCTAssertEqual(PitchEstimator.pitchMultiplier(forHz: 1000), 2)
        XCTAssertEqual(PitchEstimator.pitchMultiplier(forHz: 10), 0.5)
    }
}

final class SettingsTests: XCTestCase {
    func testDefaults() {
        let settings = AppSettings()
        XCTAssertTrue(settings.censorship)
        XCTAssertEqual(settings.quick.count, 2)
        XCTAssertEqual(settings.hotkey.display, "⌥ + Пробел")
        XCTAssertEqual(settings.glassAlpha, 0.39, accuracy: 0.001)
    }

    func testOldSettingsWithMissingKeysStillLoad() throws {
        let json = #"{"censorship": false, "glassTransparency": 100}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertFalse(settings.censorship)
        XCTAssertEqual(settings.glassAlpha, 0.05, accuracy: 0.001)
        XCTAssertEqual(settings.presets.count, 3) // недостающее взято по умолчанию
    }

    func testRoundTrip() throws {
        var settings = AppSettings()
        settings.wakePhrase = "Эй, Стив"
        settings.customVoices = [CustomVoice(name: "мой", hertz: 130)]
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }

    func testHotkeyLimits() {
        XCTAssertTrue(Hotkey(modifiers: [.control, .option], keyCode: 40, keyLabel: "K").isValid)
        XCTAssertFalse(Hotkey(modifiers: [.control, .option, .shift], keyCode: 40, keyLabel: "K").isValid)
        XCTAssertTrue(Hotkey(modifiers: [.option]).isValid) // один модификатор тоже подходит
        XCTAssertEqual(Hotkey(modifiers: [.command, .shift], keyCode: 40, keyLabel: "K").display, "⇧ + ⌘ + K")
    }
}

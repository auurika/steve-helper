import Foundation

/// Оценка основного тона голоса по записи (в герцах), чтобы «свой голос» из файла звучал с таким же тоном.
///
/// Это приближение, а не клонирование голоса: системный голос говорит с тоном, измеренным в записи.
public enum PitchEstimator {
    public static let voiceRangeHz: ClosedRange<Double> = 70...400
    /// Обычный тон, которому соответствует множитель pitch = 1.
    public static let referenceHz = 150.0

    private static let frameSize = 2048
    private static let maxSeconds = 30.0

    /// Медиана основного тона по уверенным кадрам. Nil, если голоса в записи не слышно.
    public static func estimate(samples: [Float], sampleRate: Double) -> Double? {
        let minLag = Int(sampleRate / voiceRangeHz.upperBound)
        let maxLag = Int(sampleRate / voiceRangeHz.lowerBound)
        let limit = min(samples.count, Int(sampleRate * maxSeconds))
        var estimates: [Double] = []

        var start = 0
        while start + frameSize + maxLag < limit {
            defer { start += frameSize }

            var energy: Float = 0
            for i in 0..<frameSize { energy += samples[start + i] * samples[start + i] }
            if energy / Float(frameSize) < 1e-4 { continue } // тишина

            var correlation = [Float](repeating: 0, count: maxLag - minLag + 1)
            var peak: Float = 0
            for lag in minLag...maxLag {
                var sum: Float = 0
                for i in 0..<frameSize { sum += samples[start + i] * samples[start + i + lag] }
                correlation[lag - minLag] = sum
                peak = max(peak, sum)
            }
            // самый короткий период с почти максимальной корреляцией: так не путаем тон с его октавой ниже
            let index = correlation.indices.first { i in
                correlation[i] >= peak * 0.9
                    && correlation[i] >= (i > 0 ? correlation[i - 1] : 0)
                    && correlation[i] >= (i + 1 < correlation.count ? correlation[i + 1] : 0)
            }
            if let index, peak / energy > 0.3 {
                estimates.append(sampleRate / Double(minLag + index))
            }
        }

        guard !estimates.isEmpty else { return nil }
        estimates.sort()
        return estimates[estimates.count / 2]
    }

    /// Множитель тона для синтезатора речи (диапазон AVSpeechUtterance.pitchMultiplier: 0.5...2).
    public static func pitchMultiplier(forHz hz: Double) -> Float {
        Float(min(2, max(0.5, hz / referenceHz)))
    }
}

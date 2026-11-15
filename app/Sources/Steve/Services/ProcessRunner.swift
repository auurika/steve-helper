import Foundation

/// Запуск внешних программ (`open`, `osascript`, `pmset`) с ограничением по времени.
/// Без ограничения запрос доступа к «Заметкам» без ответа пользователя подвесил бы Стива навсегда.
enum ProcessRunner {
    struct Result {
        var status: Int32
        var output: String
        var error: String
        var timedOut: Bool
    }

    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 20) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error

            let lock = NSLock()
            var finished = false
            func finish(_ result: Result) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(returning: result)
            }

            process.terminationHandler = { ended in
                let out = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                finish(Result(status: ended.terminationStatus, output: out, error: err, timedOut: false))
            }
            do {
                try process.run()
            } catch {
                finish(Result(status: -1, output: "", error: error.localizedDescription, timedOut: false))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                    finish(Result(status: -2, output: "", error: "нет ответа за \(Int(timeout)) с", timedOut: true))
                }
            }
        }
    }
}

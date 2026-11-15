// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Steve",
    defaultLocalization: "ru",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Steve", targets: ["Steve"]),
    ],
    targets: [
        // Логика без интерфейса: разбор команд, стиль ответов, оценка тона голоса. Покрыта тестами.
        .target(name: "SteveCore", path: "Sources/SteveCore"),
        // Само приложение: окно, меню-бар, Стив, речь, горячая клавиша, инструменты macOS.
        .executableTarget(name: "Steve", dependencies: ["SteveCore"], path: "Sources/Steve"),
        .testTarget(name: "SteveCoreTests", dependencies: ["SteveCore"], path: "Tests/SteveCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)

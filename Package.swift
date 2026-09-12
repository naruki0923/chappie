// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Chappie", platforms: [.macOS(.v14)], products: [.executable(name: "Chappie", targets: ["Chappie"])], targets: [.executableTarget(name: "Chappie")])

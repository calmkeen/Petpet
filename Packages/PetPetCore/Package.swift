// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PetPetCore",
    platforms: [.iOS("18.0"), .watchOS("11.0"), .macOS(.v13)],
    products: [.library(name: "PetPetCore", targets: ["PetPetCore"])],
    targets: [
        .target(name: "PetPetCore"),
        .testTarget(name: "PetPetCoreTests", dependencies: ["PetPetCore"])
    ]
)

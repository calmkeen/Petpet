// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PetPetCore",
    platforms: [.iOS("18.0"), .watchOS("11.0"), .macOS(.v13)],
    products: [
        .library(name: "PetPetCore", targets: ["PetPetCore"]),
        .library(name: "PetPetConnectivity", targets: ["PetPetConnectivity"])
    ],
    targets: [
        .target(name: "PetPetCore"),
        .target(name: "PetPetConnectivity", dependencies: ["PetPetCore"]),
        .testTarget(name: "PetPetCoreTests", dependencies: ["PetPetCore"])
    ]
)

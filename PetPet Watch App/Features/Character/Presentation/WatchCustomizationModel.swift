import Combine
import Foundation
import PetPetCore

@MainActor
final class WatchCustomizationModel: ObservableObject {
    @Published private(set) var selection: PetCustomization = .default
    @Published private(set) var hasLoaded = false
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var error: String?
    private let repository: any PetCustomizationRepository

    init(repository: any PetCustomizationRepository) { self.repository = repository }
    func load() async {
        guard !hasLoaded, !busy else { return }
        busy = true; defer { busy = false }
        do {
            selection = try await repository.load()
            hasLoaded = true; error = nil
        } catch { self.error = "꾸미기 설정을 불러오지 못했어요. 다시 시도해 주세요." }
    }
    func selectCharacter(_ id: String) async {
        guard PetCustomizationCatalog.characters.contains(where: { $0.id == id }) else { return }
        var next = selection; next.characterID = id
        await save(next)
    }
    func selectBackground(_ id: String) async {
        guard PetCustomizationCatalog.backgrounds.contains(where: { $0.id == id }) else { return }
        var next = selection; next.backgroundID = id
        await save(next)
    }
    private func save(_ next: PetCustomization) async {
        guard hasLoaded, !busy, next != selection else { return }
        busy = true; message = nil; error = nil
        defer { busy = false }
        do {
            try await repository.save(next)
            selection = next
            message = "저장했어요. 홈에서 확인해 보세요."
        } catch { self.error = "저장하지 못했어요. 기존 설정을 유지해요. 다시 시도해 주세요." }
    }
}

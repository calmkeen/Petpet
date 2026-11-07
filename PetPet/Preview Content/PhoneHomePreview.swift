#if DEBUG
import SwiftUI
import PetPetCore

#Preview {
    let pet = PetProgress.newUser(at: Date())
    let snapshot = WatchSnapshot(
        sourceID: UUID(), revision: 1, generatedAt: Date(),
        steps: [DailyStepRecord(date: StepDay(containing: Date()).date, stepCount: 7_234)],
        pet: pet.pet, inventory: pet.inventory
    )
    PhoneHomeView(viewModel: PhoneHomeViewModel(initialState: PhoneSnapshotState(
        cached: CachedWatchSnapshot(snapshot: snapshot, receivedAt: Date(), peerID: "preview")
    )), accountViewModel: AccountViewModel(), streakViewModel: PhoneStreakViewModel())
}
#endif

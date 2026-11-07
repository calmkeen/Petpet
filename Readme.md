# This project is made by @Chaeros

## What is this project?

This app is growing pets in your watch.
It can use android & ios both.
This is for people who can’t have a pet of their own but still love animals deeply.

## Apple application structure

The iPhone and Apple Watch apps use SwiftUI with feature-based MVVM. Shared domain
models, repository contracts, and sensor-session logic live in the local
`Packages/PetPetCore` Swift package. Apple framework adapters live in each app's
`Infrastructure` folder; app entry points assemble their dependencies.

- [Architecture and development flow](Docs/Architecture.md)
- [Android feature parity and implementation order](Docs/AndroidParity.md)
- [Daily steps, persistence, and recovery](Docs/DailySteps.md)
- [Feeding, growth, and step rewards](Docs/FeedingAndGrowth.md)
- [Streak calendars and nickname editing](Docs/StreakAndNickname.md)
- [iPhone and Apple Watch synchronization](Docs/WatchSynchronization.md)
- [Apple login, server backup, and restore setup](Docs/AccountAndBackup.md)
- [Required backend changes for Apple login](Docs/AppleSignInServer.md)
- [Free Personal Team testing with Debug login and mock backups](Docs/DebugTesting.md)

The watch app displays a pet and today's steps, restores calendar-day totals,
and saves daily history locally. It refreshes system pedometer history when the
app resumes and rolls over at local midnight. CoreMotion provides approximately
seven days of historical recovery; older saved records are retained. Feeding,
leveling, stat allocation, affection, and daily step rewards persist locally.
The Digital Crown switches between home, growth, food, streak, and account overview pages;
opening a management screen lets the Crown scroll its detailed list.
Release rewards are granted after a successful server backup, matching Android.
Debug uses a persistent mock backend on the iPhone and an isolated watch game copy.
The iPhone receives the watch's daily steps, pet state, and food inventory through
WatchConnectivity and keeps the latest valid snapshot for offline viewing.
It shows connection status, last sync time, and a manual refresh action. Missing
today's data is displayed as a dash. Native Sign in with Apple, Keychain sessions,
and the StepMate backup/restore client are implemented. Live account verification
requires the new Apple authentication endpoint and a developer team/profile that
supports Sign in with Apple. The server handoff guide documents those changes.
The watch provides a monthly step calendar and date selection. The phone shows
365 days of backed-up steps. Both apps can check and change a nickname; the watch
relays authenticated profile requests through the phone. Debug supports the same
flow with a persistent mock profile. Games, rankings, and voice remain subsequent milestones.

The default Debug build runs on a free Personal Team with a development login
button and no Sign in with Apple entitlement. It supports real watch sensors and
phone/watch sync, plus local mock backup, rewards, and restore. Production account
and game files are preserved. Release retains native Apple authentication.


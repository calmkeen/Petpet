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
- [iPhone and Apple Watch synchronization](Docs/WatchSynchronization.md)

The watch app displays a pet and today's steps, restores calendar-day totals,
and saves daily history locally. It refreshes system pedometer history when the
app resumes and rolls over at local midnight. CoreMotion provides approximately
seven days of historical recovery; older saved records are retained. Feeding,
leveling, stat allocation, affection, and daily step rewards persist locally.
The Digital Crown switches between home, growth, and food overview pages;
opening a management screen lets the Crown scroll its detailed list.
Rewards are claimed after a successful local save; Android's server-backup trigger
will be connected when authentication and backend integration are implemented.
The iPhone receives the watch's daily steps, pet state, and food inventory through
WatchConnectivity and keeps the latest valid snapshot for offline viewing.
It shows connection status, last sync time, and a manual refresh action. Missing
today's data is displayed as a dash. Backend services, games, and voice remain
subsequent milestones.


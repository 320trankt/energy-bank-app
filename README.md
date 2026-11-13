# Energy Bank

Personal iOS app (a proof of concept for one user) that models daily energy as two bank accounts, mental and physical. Sleep deposits into both each night, screen time withdraws from the mental bank, and workouts withdraw from the physical bank while depositing into the mental one. Quick 1–10 check-ins for mind and body are the ground truth a Claude agent tunes the model against. The full design is in [DESIGN.md](DESIGN.md).

**Status:** project layout (DESIGN.md Build Order step 1) and the core model. HealthKit import, Screen Time monitoring, check-ins and the Claude agent come next. The app hasn't been compiled on a Mac yet.

## Layout

```
App/                 SwiftUI app (iOS 17+): dashboard so far
Monitor/             DeviceActivityMonitor extension (Screen Time threshold callbacks)
EnergyBankKit/       Swift package with all logic (data model, config, two-bank model) + tests
project.yml          XcodeGen spec; `xcodegen generate` makes EnergyBank.xcodeproj
.github/workflows/   core-tests.yml (Linux, every PR) and ios.yml (your Mac → your iPhone)
docs/IOS_BUILD.md    Mac / iPhone / runner setup
```

## Develop

```bash
swift test --package-path EnergyBankKit   # runs on macOS or Linux
brew install xcodegen && xcodegen generate && open EnergyBank.xcodeproj
```

See [docs/IOS_BUILD.md](docs/IOS_BUILD.md) for building to your phone.

## The model

`EnergyModel` (in `EnergyBankKit`) replays a day in time order and returns both drain curves, the day's totals and the top drains. Every weight lives in `MonitorConfig`, so the user or the agent can tune it without code changes. The defaults are starting points, not fitted values:

- **Sleep:** minutes asleep weighted by stage and bank (deep counts more for the body, REM for the mind; unstaged sleep counts as core), minus penalties for latency past 15 minutes and time awake. 8 hours of core-weighted sleep deposits 100 points.
- **Screen time:** each threshold rung costs its minutes × a per-category rate, from 0.4/min for social and games to 0.1/min for productivity.
- **Workouts:** physical cost scales with duration and intensity (heart rate zones, else active energy, else duration only). The mental deposit has diminishing returns, up to 20 points, and shrinks when the physical bank is below 30.

Costs and deposits are computed from the config rather than stored with each event, so a retuned config re-scores past days too.

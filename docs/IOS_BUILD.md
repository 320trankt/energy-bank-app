# Building Energy Bank for an iPhone

This uses the same Mac, Apple ID and phone setup as tinyball, warcell and bite-check. If bite-check already builds to your phone, the new parts are the repo visibility, the capabilities, a fourth runner and two variables (steps marked **new**).

Written without a Mac: the core library (`EnergyBankKit`) is compiled and tested on Linux, but the SwiftUI app and the Screen Time extension have not been compiled yet. Expect the first Xcode build to need a fix or two.

## Before the first build: make the repo private (new)

This repo is public. Keep the Mac's runners off public repos, as with warcell: a pull request from a fork can bring its own workflow file aimed at the runner's labels. Settings → General → Danger Zone → **Change visibility** → Private, before registering the runner below.

## Capabilities and signing (new)

Energy Bank needs three capabilities the other apps don't. `project.yml` generates the entitlements, and automatic signing (`-allowProvisioningUpdates`) registers them with the team:

| Capability | Targets | Used for |
|---|---|---|
| HealthKit | app | Reading sleep, workouts, heart rate and active energy |
| Family Controls | app, monitor | Screen Time authorization and threshold callbacks |
| App Groups (`group.com.kalisoft.energybank`) | app, monitor | Storage shared between the app and the extension |

- **Team:** a free Personal Team may not provision all three; I couldn't check which ones it allows. If the first build fails with a provisioning error naming one of them, sign with the Kali-Soft team instead, the switch already planned for the other apps.
- **TestFlight:** before any build with Family Controls can go to TestFlight or the App Store, Apple has to approve the Family Controls distribution entitlement (requested at developer.apple.com). Development builds installed by this workflow don't need it.
- **Real iPhone:** test Screen Time monitoring on the phone; the Simulator is fine for the UI.

## One-time Mac setup

Xcode, the Apple ID, iPhone trust, Developer Mode and XcodeGen are as in bite-check's `docs/IOS_BUILD.md`. Nothing new.

## Build and run by hand

```bash
git clone https://github.com/320trankt/energy-bank-app.git
cd energy-bank-app
swift test --package-path EnergyBankKit   # core logic tests, a few seconds
xcodegen generate                         # writes EnergyBank.xcodeproj
open EnergyBank.xcodeproj
```

In Xcode, for both the **EnergyBank** and **EnergyBankMonitor** targets: **Signing & Capabilities** → tick *Automatically manage signing* → choose your Team. Pick your iPhone as the run destination and press **⌘R**.

- **Bundle identifiers:** `com.kalisoft.energybank` and `com.kalisoft.energybank.monitor` (an extension's ID must start with its app's).
- After editing `project.yml` or adding or removing files, run `xcodegen generate` again.

## Automatic builds to your phone

`.github/workflows/ios.yml` is bite-check's workflow with the names changed: on every push to `main` the Mac runs the unit tests, generates the project, builds, signs, installs on the iPhone and launches it. You can also run it by hand on any branch (Actions → **iOS build** → *Run workflow* → pick the branch) to try a pull request on your phone before merging. It never runs for pull requests.

Until `APPLE_TEAM_ID` is set on this repo the job is skipped, so pushes don't wait for a runner that isn't registered yet. Set it last.

1. **Runner (new):** a self-hosted runner serves one repository, so add a fourth on the Mac mini. This repo → Settings → Actions → Runners → **New self-hosted runner** → macOS (ARM64). Run its *Download* and *Configure* commands in a new folder, `~/actions-runner-energy-bank`. When `config.sh` asks for **additional labels**, enter `energy-bank`.
2. **Keep it running:** re-run macmini-ops's `setup.sh`, which installs every `~/actions-runner*` folder as a service without `SessionCreate` (otherwise signing fails with `errSecInternalComponent`), and add the runner to the Mac's machine notes. By hand, in the runner folder:

   ```bash
   ./svc.sh install && ./svc.sh start
   ./svc.sh stop
   /usr/libexec/PlistBuddy -c 'Delete :SessionCreate' ~/Library/LaunchAgents/actions.runner.320trankt-energy-bank-app.*.plist
   ./svc.sh start
   ```

3. **Variables (new):** this repo → Settings → Secrets and variables → Actions → **Variables**:
   - `IPHONE_IDS`: **your own iPhone's UDID only** (the `00008…` value in `xcrun devicectl list devices`). The app reads your health and Screen Time data, so it shouldn't go to family phones. If `IPHONE_IDS` later becomes a Kali-Soft org variable, keep this repo-level one: a repository variable overrides the org's.
   - `APPLE_TEAM_ID`: the same Team ID as the other apps (see *Capabilities and signing*).
4. **First run:** Actions → **iOS build** → *Run workflow*. Untick *Install on the iPhone* to only build and test.

When the Kali-Soft org runners exist, `runs-on` changes to their labels and this repo's own runner can be removed.

`.github/workflows/core-tests.yml` runs the `EnergyBankKit` tests on a GitHub-hosted Linux runner for every push and pull request; it doesn't need the Mac. It uses Swift 6.3.2, the Swift in Xcode 26.5, the Mac's active Xcode. If the Mac switches to Xcode 27, move the CI image and the cloud environment's setup script to Swift 6.4.

## Troubleshooting

- **The iOS build is skipped:** `APPLE_TEAM_ID` isn't set on this repo.
- **"No such module 'EnergyBankKit'":** run `xcodegen generate` again and let Xcode finish resolving packages (File → Packages → Resolve Package Versions).
- **Provisioning errors naming HealthKit, Family Controls or App Groups:** see *Capabilities and signing*.
- **Other signing errors:** see tinyball's troubleshooting; the setup is the same.

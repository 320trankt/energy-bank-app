# Energy Bank — iOS App POC Design Document

## Overview

Energy Bank is a personal iOS app that models daily energy as a bank account: sleep makes a deposit each night, and screen time throughout the day makes withdrawals. The app collects sleep data from Apple Health (written by Fitbit and Bevel), logs screen-time usage events via Apple's Screen Time APIs, and feeds a daily summary to a specialized Claude agent that estimates the energy balance and identifies what drains it fastest.

This is a proof of concept for a single user (the developer). Polish, multi-user support, and App Store compliance are out of scope.

## Goals

- Capture nightly sleep (duration, stages, in-bed vs. asleep) from HealthKit.
- Capture daytime screen usage per app and per category as stepwise threshold events.
- Compute a daily energy balance: deposit from sleep, withdrawals from screen time.
- Send a structured daily summary to a Claude agent and display its analysis.
- Store history locally so trends can be reviewed over weeks.

## Non-Goals (POC)

- Exact per-app screen-time totals (not exposed by the API).
- Tracking background media (picture-in-picture YouTube, audio) — only foreground time counts.
- Counting app switches or pickups (possible later via Shortcuts automations).
- Any backend, accounts, or sync.

## Core Model

The app tracks two separate banks, mental energy and physical energy. Sleep deposits into both. Screen time withdraws from the mental bank. Workouts withdraw from the physical bank in the short term but deposit into the mental bank, modeling the observed effect that exercise relieves mental fatigue. The two banks are coupled: a very low physical bank reduces the mental benefit of a workout, and the agent learns the coupling from check-ins.

- **Sleep deposit**: credited to both banks from last night's sleep. Baseline formula for POC: total asleep minutes, weighted by stage (deep and REM count more than core), minus a penalty for long sleep latency (in-bed minus asleep) and awake segments. Separate stage weights per bank so the model can learn, for example, that deep sleep matters more physically and REM more mentally.
- **Mental withdrawal**: each screen-time threshold event logs a fixed cost against the mental bank. Cost per rung can vary by category (e.g., social and games cost more than productivity).
- **Workout effect**: each HealthKit workout logs a physical withdrawal scaled by duration and intensity (heart rate zones or active energy), and a mental deposit scaled by duration with diminishing returns. Workout type can carry its own weights (e.g., climbing vs. volleyball vs. walking).
- **Balances**: two running numbers, each deposit minus withdrawals so far today. Displayed as two drain curves over the day.
- Weights, costs, and coupling factors are config values, not hard-coded, so the Claude agent or the user can tune them against check-in data.

## Data Sources

### Sleep — HealthKit

- Request read access to `HKCategoryTypeIdentifier.sleepAnalysis`.
- Read samples from the previous night's window (e.g., 6 PM yesterday to noon today).
- Handle multiple sources (Fitbit, Bevel, Apple Watch): pick a primary source or merge by priority to avoid double-counting.
- Extract: in-bed segments, asleep segments by stage (core, deep, REM), awake segments.
- Optionally read overnight heart rate and HRV as secondary signals (future).

### Workouts — HealthKit

- Request read access to `HKWorkoutType`, `activeEnergyBurned`, and `heartRate`.
- Read today's workouts: type, start and end, duration, active energy, and average heart rate where available.
- Compute an intensity score from heart rate zones or active energy per minute; fall back to duration only when neither is present.
- Each workout produces one `WorkoutEvent` applied to both banks per the core model.

### Screen Time — Screen Time API

- Frameworks: `FamilyControls`, `ManagedSettings`, `DeviceActivity`.
- Request authorization with `AuthorizationCenter` (individual mode).
- Present `FamilyActivityPicker` so the user selects apps and categories to monitor.
- Store the resulting `FamilyActivitySelection` (opaque app and category tokens).
- Create a `DeviceActivityMonitor` extension. Register a daily `DeviceActivitySchedule` and, for each monitored app/category, a ladder of `DeviceActivityEvent` thresholds.
- In the extension, `eventDidReachThreshold` writes a withdrawal record (token id, rung, timestamp) to a shared App Group container.

#### Threshold ladder design

- Rung size: 5 minutes for closely watched apps, 10–15 minutes for the rest. Configurable.
- Events per schedule are limited (plan for roughly 20). When an app nears the top of its ladder, the extension re-registers the schedule with a new ladder starting from the current level.
- Callbacks may fire slightly late; treat rung times as approximate.

#### App identity

- Tokens are opaque; the app cannot read app names as strings.
- One-time setup screen lets the user assign a nickname and category to each selected token using `Label(token)` for the visual.
- Nicknames are what get sent to Claude.

## Energy Check-Ins

Subjective energy ratings are the ground truth the model is fitted against. Each check-in records two ratings, mental energy and physical energy, each a single tap on a 1–10 scale, logged with a timestamp, and sent to the Claude agent alongside sleep and screen-time data so it can tune deposit and withdrawal weights to how the user actually feels.

### Widget (primary input)

- Built with WidgetKit and App Intents so a tap records a rating without opening the app.
- Home screen: a small or medium interactive widget showing today's balance and a row of tappable energy buttons. Medium size shows two labeled rows, Mind and Body, each 1–10; small size shows two compact 5-step rows (1, 3, 5, 7, 10) that map to the same scale. A tap on one row logs that axis; the widget holds the pending pair for a few seconds so both can be tapped, then saves.
- Lock screen: accessory widgets. A rectangular widget with two compact 5-step rows (Mind, Body) plus the last ratings and time; a circular widget showing the current balance as a gauge that deep-links to the check-in sheet.
- Each button is an `AppIntent` (`LogEnergyIntent(level:)`) that writes a `CheckIn` to the shared App Group store and reloads widget timelines.
- Visual style: soft rounded shapes, a battery or sun-style gauge that fills with the balance, pastel gradient from warm (low) to bright (high), and a small friendly mascot face that changes expression with the last rating. Haptic tap on log. Should feel playful and take under a second to use.
- After logging, the widget shows a brief "Logged 7 — 2:14 PM" state for a few minutes, then returns to the prompt.

### Prompts

- Scheduled local notifications at configurable times (default: morning, early afternoon, evening). Notifications use a category with 1–10 action buttons so a rating can be logged from the notification itself.
- Check-in also offered on app open if none has been logged in the last few hours.
- Prompt wording frames the rating relative to the user's usual ("compared to your normal, how's your energy?") to reduce scale drift.

### Data

- `CheckIn`: id, timestamp, mentalLevel (1–10), physicalLevel (1–10), source (widget, notification, app).
- Included in the daily agent payload as a timestamped series.
- The agent normalizes levels over a rolling window and correlates them against sleep deposit and withdrawal events, including time lag.

## Architecture

- **Main app (SwiftUI)**: onboarding/authorization, app selection and nicknaming, dashboard, history, Claude analysis view.
- **DeviceActivityMonitor extension**: receives threshold callbacks, appends withdrawal events to shared storage.
- **Shared storage**: App Group container with a lightweight store (SwiftData or SQLite) holding sleep summaries, withdrawal events, daily balances, and Claude responses.
- **Sleep importer**: runs on app open and via background refresh each morning; pulls last night's HealthKit samples and computes the deposit.
- **Claude agent client**: builds the daily summary payload and calls the Anthropic API.
- **Widget extension (WidgetKit + App Intents)**: home and lock screen energy check-in widgets writing to the shared store.

## Claude Agent

- Input: a JSON summary per day containing sleep deposit details, the list of withdrawal events with nicknames, categories, and timestamps, current config weights, and the last 7 days of balances.
- System prompt frames the agent as an energy-budget analyst: estimate today's balance, name the top drains, note patterns across the week, and suggest one concrete adjustment.
- Output: short natural-language analysis plus an optional structured block with suggested weight changes the user can accept.
- POC calls the API directly from the device with a key stored in Keychain. No backend.

## Data Model (sketch)

- `SleepSummary`: date, inBedStart, inBedEnd, asleepMinutes, deepMinutes, remMinutes, coreMinutes, awakeMinutes, latencyMinutes, source, depositValue.
- `WithdrawalEvent`: id, date, timestamp, tokenId, nickname, category, rungMinutes, cost.
- `AgentResponse`: date, text, suggestedConfig.
- `MonitorConfig`: rung sizes, cost per category, stage weights, latency penalty.
- `CheckIn`: id, timestamp, mentalLevel, physicalLevel, source.
- `WorkoutEvent`: id, date, start, end, workoutType, durationMinutes, activeEnergy, avgHeartRate, intensity, physicalCost, mentalDeposit.
- `DailyBalance`: date, mentalDeposit, mentalWithdrawals, mentalBalance, physicalDeposit, physicalWithdrawals, physicalBalance.

## Screens

1. Onboarding: HealthKit and Screen Time authorization.
2. App selection: FamilyActivityPicker, then nickname and category assignment.
3. Dashboard: today's deposit, running balance, drain curve, top withdrawals.
4. History: list of past days with balance and a trend chart.
5. Analysis: the Claude agent's daily read-out and accept/reject for suggested tuning.
6. Settings: rung sizes, costs, weights, API key.

## Build Order

1. Project setup: app target, DeviceActivityMonitor extension, App Group, entitlements (HealthKit, Family Controls).
2. HealthKit sleep import and deposit calculation; show it on the dashboard.
3. Screen Time authorization, picker, token storage, nicknaming.
4. Monitor extension with threshold ladder; verify events land in shared storage.
5. Balance computation and drain curve.
6. Claude agent client and analysis screen.
7. History and trend view.
8. Energy check-in widget extension (home and lock screen) and scheduled notification prompts; include check-ins in the agent payload.

## Known Limitations and Risks

- Family Controls entitlement must be requested from Apple for distribution; it works on a development device without it.
- Foreground-only accounting: background video and audio are invisible.
- Threshold events, not totals: usage between rungs is unknown.
- Event cap per schedule requires re-registration logic.
- Multiple sleep sources can overlap; dedupe logic needed.
- Extension runs with tight memory and time limits; keep the write path minimal.

## Open Questions

- Exact deposit formula and stage weights to start with.
- Whether to add a Shortcuts automation for pickup/switch counting in a later phase.
- Whether HRV or resting heart rate should feed the deposit.

## Future Upgrades

- Caffeine and nutrition logging as inputs to both the mental and physical banks. Deliberately out of scope for the POC.

import DeviceActivity

/// Receives Screen Time threshold callbacks for the monitored apps (DESIGN.md, Screen Time).
/// The system gives extensions tight memory and time limits, so the write path must stay minimal.
///
/// Empty for now: it's here so the first Mac build proves the Family Controls and App Group
/// entitlements sign. Build Order step 4 adds `eventDidReachThreshold`, which appends a
/// `WithdrawalEvent` to the App Group container (`AppGroup.containerURL` in EnergyBankKit).
final class EnergyMonitor: DeviceActivityMonitor {}

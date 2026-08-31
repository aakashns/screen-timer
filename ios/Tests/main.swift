import Foundation

let cal = Calendar.current
let day = cal.startOfDay(for: Date())
let suite = "tick.test.\(UUID().uuidString)"
let store = ScreenTimeStore(defaults: UserDefaults(suiteName: suite)!)

var failures = 0
func check(_ label: String, _ got: String, _ want: String) {
    let ok = got == want
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(label): got \(got), want \(want)")
}

// Nothing recorded yet.
check("empty reads zero", ScreenTimeStore.formatted(store.snapshot(now: day).confirmed), "00:00")

// A milestone lands at 09:00 confirming 1h15m of screen time.
let nine = day.addingTimeInterval(9 * 3600)
store.record(seconds: 75 * 60, at: nine)
var snap = store.snapshot(now: nine)
check("milestone reads back", ScreenTimeStore.formatted(snap.confirmed), "01:15")

// The timer must read exactly the confirmed value at the milestone instant.
check("reads confirmed at asOf", ScreenTimeStore.formatted(snap.estimate(now: nine)), "01:15")

// Five minutes later it should have ticked five minutes.
check("ticks forward", ScreenTimeStore.formatted(snap.estimate(now: nine.addingTimeInterval(300))), "01:20")

// Past one step it must freeze, so a screen-off gap cannot run away.
check("freezes after one step",
      ScreenTimeStore.formatted(snap.estimate(now: nine.addingTimeInterval(8 * 3600))), "01:30")

// The widget's range must agree with estimate() at both ends.
let lower = snap.timerRange.lowerBound, upper = snap.timerRange.upperBound
check("range starts confirmed before asOf", "\(Int(nine.timeIntervalSince(lower)))", "4500")
check("range ends one step after asOf", "\(Int(upper.timeIntervalSince(nine)))", "\(Int(Milestones.step))")
check("range is ordered", "\(lower <= upper)", "true")

// Late, duplicate and out-of-order thresholds must never lower the total.
store.record(seconds: 30 * 60, at: nine.addingTimeInterval(60))
check("never moves down", ScreenTimeStore.formatted(store.snapshot(now: nine).confirmed), "01:15")

// Yesterday's milestone must not leak into today.
let store2 = ScreenTimeStore(defaults: UserDefaults(suiteName: suite)!)
let tomorrow = cal.date(byAdding: .day, value: 1, to: day)!
check("day rollover zeroes",
      ScreenTimeStore.formatted(store2.snapshot(now: tomorrow).confirmed), "00:00")

// The ladder must be monotonic and cover what it claims.
check("ladder first step", "\(Int(Milestones.seconds(at: 0)))", "900")
check("ladder coverage hours", "\(Int(Milestones.seconds(at: Milestones.count - 1)) / 3600)", "8")
check("name round-trips", "\(Milestones.index(from: Milestones.name(at: 17)) ?? -1)", "17")
check("rejects foreign name", "\(Milestones.index(from: "bogus") == nil)", "true")

UserDefaults().removePersistentDomain(forName: suite)
print(failures == 0 ? "\nAll checks passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)

import DeviceActivity

extension DeviceActivityReport.Context {
    /// Identifies the scene in the report extension that renders today's real
    /// Screen Time total. Named on both sides, so it lives in shared code.
    static let totalActivity = Self("Total Activity")
}

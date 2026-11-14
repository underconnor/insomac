import Darwin

@main
struct MachTimebaseTests {
    static func main() throws {
        let arm = try MachTimebase(numerator: 125, denominator: 3)
        precondition(abs(arm.nanoseconds(forTicks: 24_000_000) - 1_000_000_000) < 0.001)
        let intel = try MachTimebase(numerator: 1, denominator: 1)
        precondition(intel.nanoseconds(forTicks: 123_456_789) == 123_456_789)
        precondition(arm.nanoseconds(forTicks: .max).isFinite)
        do {
            _ = try MachTimebase(numerator: 1, denominator: 0)
            preconditionFailure("A zero denominator must fail.")
        } catch MachTimebaseFailure.unavailable {}
        print("PASS: non-unit Mach timebase scaling, unit scaling, large counters, and invalid timebase")

        let timebase = try MachTimebase.current()
        var beforeUsage = rusage()
        precondition(getrusage(RUSAGE_SELF, &beforeUsage) == 0)
        let beforeTicks = cpuTicks()
        let started = mach_absolute_time()
        var checksum: UInt64 = 1
        while timebase.nanoseconds(forTicks: mach_absolute_time() - started) < 150_000_000 {
            checksum = checksum &* 6_364_136_223_846_793_005 &+ 1
        }
        let afterTicks = cpuTicks()
        var afterUsage = rusage()
        precondition(getrusage(RUSAGE_SELF, &afterUsage) == 0)
        let scaled = timebase.nanoseconds(forTicks: afterTicks - beforeTicks) / 1e9
        let reference = seconds(afterUsage) - seconds(beforeUsage)
        precondition(reference > 0.05, "The fixture did not accumulate enough CPU time.")
        precondition(abs(scaled - reference) < 0.02, "Scaled proc_pid_rusage disagrees with getrusage.")
        print("PASS: native CPU counter scale agrees with independent getrusage; checksum \(checksum)")
    }

    private static func cpuTicks() -> UInt64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { value in
            value.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        precondition(result == 0)
        return info.ri_user_time + info.ri_system_time
    }

    private static func seconds(_ value: rusage) -> Double {
        Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec)
            + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1e6
    }
}

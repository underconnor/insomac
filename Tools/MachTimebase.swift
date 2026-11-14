import Darwin

enum MachTimebaseFailure: Error {
    case unavailable
}

struct MachTimebase {
    let numerator: UInt32
    let denominator: UInt32

    init(numerator: UInt32, denominator: UInt32) throws {
        guard numerator > 0, denominator > 0 else { throw MachTimebaseFailure.unavailable }
        self.numerator = numerator
        self.denominator = denominator
    }

    static func current() throws -> Self {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS else { throw MachTimebaseFailure.unavailable }
        return try Self(numerator: info.numer, denominator: info.denom)
    }

    func nanoseconds(forTicks ticks: UInt64) -> Double {
        // Convert before reporting: proc_pid_rusage CPU counters use Mach ticks.
        // Floating point avoids overflow when scaling a large cumulative value.
        Double(ticks) * Double(numerator) / Double(denominator)
    }
}

import Foundation
import Darwin

enum Sys {
    static func sysctlInt(_ name: String) -> Int? {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return Int(v)
    }

    static func bootDate() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0, tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
    }

    /// Runs an absolute-path executable with an argv list. nil on launch failure or timeout.
    /// stdout and stderr are merged into the returned text.
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 5) -> (status: Int32, output: String)? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }

        let box = DataBox()
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = done.wait(timeout: .now() + 1)
            return nil
        }
        _ = readDone.wait(timeout: .now() + 1)
        return (p.terminationStatus, String(decoding: box.data, as: UTF8.self))
    }
}

private final class DataBox: @unchecked Sendable { var data = Data() }

/// A value cached for a fixed time, including a cached nil (so a failing command is not retried every minute).
final class TimedCache<T>: @unchecked Sendable {
    private let lock = NSLock()
    private let ttl: TimeInterval
    /// A failed or timed-out read (nil) is retried sooner than a good one.
    private let nilTTL: TimeInterval
    private var stamp: Date?
    private var value: T?
    init(ttl: TimeInterval, nilTTL: TimeInterval = 300) { self.ttl = ttl; self.nilTTL = min(ttl, nilTTL) }

    /// With `allowProduce` false the stored value is returned even if expired and nothing is launched.
    func get(now: Date, allowProduce: Bool = true, _ produce: () -> T?) -> T? {
        lock.lock()
        if !allowProduce { let v = value; lock.unlock(); return v }
        if let s = stamp, now.timeIntervalSince(s) < (value == nil ? nilTTL : ttl), now >= s { let v = value; lock.unlock(); return v }
        lock.unlock()
        let v = produce()
        lock.lock(); stamp = now; value = v; lock.unlock()
        return v
    }
}

import Foundation

public enum MemoryPressure: Int, Sendable, Codable, Comparable {
    case normal, warning, critical
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum ThermalLevel: Int, Sendable, Codable, Comparable {
    case nominal, fair, serious, critical
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// One visible app with its helper processes already rolled up.
public struct AppUsage: Sendable, Equatable, Codable {
    public var name: String
    public var bundleID: String
    /// 100 means one full core.
    public var cpuPercent: Double
    /// CPU used by processes inside the app's own bundle only. nil means the same as `cpuPercent`.
    /// Jobs started from a terminal or editor are children but not part of the app, so they don't count here.
    public var ownCPUPercent: Double?
    public var memoryBytes: UInt64
    /// Memory of the app's own processes only. nil means the same as `memoryBytes`.
    public var ownMemoryBytes: UInt64?
    public var isFrontmost: Bool

    public init(name: String, bundleID: String, cpuPercent: Double, ownCPUPercent: Double? = nil,
                memoryBytes: UInt64, ownMemoryBytes: UInt64? = nil, isFrontmost: Bool = false) {
        self.ownCPUPercent = ownCPUPercent
        self.ownMemoryBytes = ownMemoryBytes
        self.name = name
        self.bundleID = bundleID
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.isFrontmost = isFrontmost
    }
}

public struct BatteryReading: Sendable, Equatable, Codable {
    public var present: Bool
    public var cycleCount: Int?
    public var maxCapacityPercent: Int?
    public var serviceRecommended: Bool?

    public init(present: Bool, cycleCount: Int? = nil, maxCapacityPercent: Int? = nil, serviceRecommended: Bool? = nil) {
        self.present = present
        self.cycleCount = cycleCount
        self.maxCapacityPercent = maxCapacityPercent
        self.serviceRecommended = serviceRecommended
    }
}

public enum BackupState: Sendable, Equatable, Codable {
    case date(Date)
    case never
}

/// One set of readings. Every reading is nil when it could not be read.
public struct Snapshot: Sendable, Equatable {
    public var date: Date
    public var memoryPressure: MemoryPressure?
    public var thermal: ThermalLevel?
    public var apps: [AppUsage]?
    /// Percent of all cores busy, 0 to 100.
    public var totalCPUBusy: Double?
    /// Free space including what macOS can reclaim.
    public var freeBytes: UInt64?
    public var totalBytes: UInt64?
    public var diskHealthy: Bool?
    /// nil = unknown, present == false = a Mac without a battery.
    public var battery: BatteryReading?
    public var uptime: TimeInterval?
    public var fileVaultOn: Bool?
    public var firewallOn: Bool?
    /// nil = unknown.
    public var lastBackup: BackupState?
    public var updateWaiting: Bool?
    public var physicalMemoryBytes: UInt64?

    public init(date: Date,
                memoryPressure: MemoryPressure? = nil, thermal: ThermalLevel? = nil,
                apps: [AppUsage]? = nil, totalCPUBusy: Double? = nil,
                freeBytes: UInt64? = nil, totalBytes: UInt64? = nil, diskHealthy: Bool? = nil,
                battery: BatteryReading? = nil, uptime: TimeInterval? = nil,
                fileVaultOn: Bool? = nil, firewallOn: Bool? = nil, lastBackup: BackupState? = nil,
                updateWaiting: Bool? = nil, physicalMemoryBytes: UInt64? = nil) {
        self.date = date
        self.memoryPressure = memoryPressure
        self.thermal = thermal
        self.apps = apps
        self.totalCPUBusy = totalCPUBusy
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
        self.diskHealthy = diskHealthy
        self.battery = battery
        self.uptime = uptime
        self.fileVaultOn = fileVaultOn
        self.firewallOn = firewallOn
        self.lastBackup = lastBackup
        self.updateWaiting = updateWaiting
        self.physicalMemoryBytes = physicalMemoryBytes
    }
}

public enum Band: Sendable, Equatable {
    case healthy, couldUseCare, needsYou

    public static func forScore(_ score: Int) -> Band {
        score >= 85 ? .healthy : (score >= 65 ? .couldUseCare : .needsYou)
    }
}

public struct NumberRow: Sendable, Equatable {
    public let label: String
    public let value: String
    public init(_ label: String, _ value: String) { self.label = label; self.value = value }
}

public struct AreaStatus: Sendable, Equatable, Identifiable {
    public let id: String
    public let symbol: String
    public let status: String
    public let explain: String
    public let level: Double
    public let numbers: [NumberRow]
    public init(id: String, symbol: String, status: String, explain: String, level: Double, numbers: [NumberRow]) {
        self.id = id; self.symbol = symbol; self.status = status
        self.explain = explain; self.level = level; self.numbers = numbers
    }
}

public struct Report: Sendable, Equatable {
    public let score: Int
    public let band: Band
    /// Visible fixes only: snoozed ones are removed, at most three.
    public let fixes: [Fix]
    public let areas: [AreaStatus]
}

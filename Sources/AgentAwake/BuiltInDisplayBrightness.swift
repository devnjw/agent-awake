import CoreGraphics
import Darwin
import Foundation

// Brightness changes belong to the guard so UI termination still runs cleanup.
// Read/write closures allow tests to exercise restoration without touching screens.
final class BuiltInDisplayBrightness {
    private let displays: () -> [UInt32]
    private let read: (UInt32) throws -> Float
    private let write: (UInt32, Float) throws -> Void
    private var originals: [UInt32: Float] = [:]
    private var openLevels: [UInt32: Float] = [:]
    private var dimmed: Set<UInt32> = []

    init(displays: @escaping () -> [UInt32], read: @escaping (UInt32) throws -> Float,
         write: @escaping (UInt32, Float) throws -> Void) {
        self.displays = displays; self.read = read; self.write = write
    }

    static func live() -> BuiltInDisplayBrightness {
        let service = DisplayBrightnessService()
        return BuiltInDisplayBrightness(displays: { service.builtInDisplays() },
            read: { try service.get($0) }, write: { try service.set($0, $1) })
    }

    func update(active: Bool, lidClosed: Bool?) throws {
        if !active || lidClosed == false {
            try restore()
            if lidClosed == false {
                // Capture while open: macOS may change what brightness reads
                // after the internal display leaves the online list.
                for id in displays() {
                    if let value = try? read(id), value.isFinite, (0...1).contains(value) {
                        openLevels[id] = value
                    } else { openLevels.removeValue(forKey: id) }
                }
            }
            return
        }
        // Unknown lid readings must neither dim an open screen nor discard
        // the brightness saved during a previous closed-lid reading.
        guard lidClosed == true else { return }
        let ids = displays()
        // A closed built-in panel may be removed from the online list entirely.
        // There is no visible internal screen to dim; external screens stay unchanged.
        guard !ids.isEmpty else { return }
        for id in ids where !dimmed.contains(id) {
            if originals[id] == nil {
                let value = try openLevels[id] ?? read(id)
                guard value.isFinite, (0...1).contains(value) else { throw BrightnessError.unavailable }
                originals[id] = value
            }
            // Save the original before writing, even if the setter fails.
            try write(id, 0)
            dimmed.insert(id)
        }
    }

    func restore() throws {
        var failure: Error?
        for (id, value) in originals {
            do {
                try write(id, value)
                originals.removeValue(forKey: id)
                dimmed.remove(id)
            } catch { if failure == nil { failure = error } }
        }
        if let failure { throw failure }
    }
}

private enum BrightnessError: LocalizedError {
    case unavailable
    case operation(String, Int32)
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Built-in display brightness control isn't available on this Mac."
        case .operation(let name, let code): return "Display brightness \(name) failed (\(code))."
        }
    }
}

// Apple Silicon brightness requires the private DisplayServices framework.
// Resolve it at runtime and fail gracefully; keep-awake assertions are independent.
private final class DisplayBrightnessService {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private let handle: UnsafeMutableRawPointer?
    private let getter: GetBrightness?
    private let setter: SetBrightness?
    private var knownBuiltIn: Set<UInt32> = []

    init() {
        handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL)
        if let handle, let get = dlsym(handle, "DisplayServicesGetBrightness"),
           let set = dlsym(handle, "DisplayServicesSetBrightness") {
            getter = unsafeBitCast(get, to: GetBrightness.self)
            setter = unsafeBitCast(set, to: SetBrightness.self)
        } else { getter = nil; setter = nil }
        // Cache the internal ID before lid closure removes it from the online list.
        _ = builtInDisplays()
    }

    func builtInDisplays() -> [UInt32] {
        var count: UInt32 = 0
        if CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 {
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            if CGGetOnlineDisplayList(count, &ids, &count) == .success {
                for id in ids.prefix(Int(count)) where CGDisplayIsBuiltin(id) != 0 {
                    knownBuiltIn.insert(id)
                }
            }
        }
        return knownBuiltIn.sorted()
    }

    func get(_ id: UInt32) throws -> Float {
        guard let getter else { throw BrightnessError.unavailable }
        var value: Float = 0
        let code = getter(id, &value)
        guard code == 0 else { throw BrightnessError.operation("read", code) }
        return value
    }

    func set(_ id: UInt32, _ value: Float) throws {
        guard let setter else { throw BrightnessError.unavailable }
        let code = setter(id, value)
        guard code == 0 else { throw BrightnessError.operation("write", code) }
    }

    deinit { if let handle { dlclose(handle) } }
}

import AppKit

enum HUDLevelValidation {
    static func normalized(_ value: Float, status: Int32) -> Double? {
        guard status == 0, value.isFinite, (0...1).contains(value) else { return nil }
        return Double(value)
    }
}

@MainActor
final class HUDBrightnessReader {
    typealias Read = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    static let shared = HUDBrightnessReader(read: load())
    private let read: Read?

    init(read: Read?) { self.read = read }

    func level(displayID: UInt32) -> Double? {
        guard let read else { return nil }
        var value = Float.nan
        let status = read(displayID, &value)
        return HUDLevelValidation.normalized(value, status: status)
    }

    private static func load() -> Read? {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { return nil }
        guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else {
            dlclose(handle)
            return nil
        }
        return unsafeBitCast(symbol, to: Read.self)
    }
}

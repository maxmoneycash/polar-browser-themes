import Foundation

// Borrowed Swift String storage stays alive throughout the native navigation call.
@_cdecl("ZenWithString")
public func withNativeString(_ text: UnsafePointer<CChar>, _ context: UnsafeMutableRawPointer?,
                             _ callback: @convention(c) (UInt, UInt, UnsafeMutableRawPointer?) -> Void) {
    let value = String(cString: text)
    withUnsafeBytes(of: value) { bytes in
        let words = bytes.bindMemory(to: UInt.self)
        callback(words[0], words[1], context)
    }
}

// Consume the +1 String returned by a native Swift getter, bridging it to a +1
// NSString. Deinitializing through Swift handles both small and heap strings.
@_cdecl("ZenTakeString")
public func takeNativeString(_ first: UInt, _ second: UInt) -> UnsafeMutableRawPointer {
    let storage = UnsafeMutablePointer<String>.allocate(capacity: 1)
    storage.withMemoryRebound(to: UInt.self, capacity: 2) { $0[0] = first; $0[1] = second }
    let result = Unmanaged.passRetained(storage.pointee as NSString).toOpaque()
    storage.deinitialize(count: 1)
    storage.deallocate()
    return result
}

// Consume a +1 Array from WindowGroupController.tabs without recreating the app's
// private Swift types. All members are borrowed during the synchronous callback.
@_cdecl("ZenEnumerateTabs")
public func enumerateNativeTabs(_ raw: UInt, _ context: UnsafeMutableRawPointer?,
                               _ callback: @convention(c) (Int, UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void) {
    let storage = UnsafeMutablePointer<[AnyObject]>.allocate(capacity: 1)
    storage.withMemoryRebound(to: UInt.self, capacity: 1) { $0.pointee = raw }
    for (index, object) in storage.pointee.enumerated() {
        callback(index, Unmanaged.passUnretained(object).toOpaque(), context)
    }
    storage.deinitialize(count: 1)
    storage.deallocate()
}

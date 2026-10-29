import AppKit

/// A short-lived, listen-only acknowledgement for our own tagged event. No keyboard input is monitored.
/// The owner must receive the event after it has reached the system session, not after an assumed sleep.
@MainActor
final class StatusEventRelay {
    private let event: CGEvent
    private let pid: pid_t
    private let tag = Int64.random(in: 1...Int64.max)
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var continuation: CheckedContinuation<Void, Error>?

    init(event: CGEvent, pid: pid_t) { self.event = event; self.pid = pid }

    func deliver() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            event.setIntegerValueField(.eventSourceUserData, value: tag)
            port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                     eventsOfInterest: CGEventMask(1) << event.type.rawValue,
                                     callback: { _, _, received, context in
                guard let context else { return Unmanaged.passUnretained(received) }
                let relay = Unmanaged<StatusEventRelay>.fromOpaque(context).takeUnretainedValue()
                if received.getIntegerValueField(.eventSourceUserData) == relay.tag {
                    relay.event.postToPid(relay.pid)
                    relay.finish(nil)
                }
                return Unmanaged.passUnretained(received)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
            guard let port else { finish(ItemMoveError.permission); return }
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            event.post(tap: .cgSessionEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.finish(ItemMoveError.unsupported) }
        }
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        port = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}

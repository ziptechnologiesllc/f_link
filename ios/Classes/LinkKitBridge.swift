import Foundation
import Flutter

/// Bridge between Flutter and LinkKit framework
///
/// Manages the ABLLink instance and provides thread-safe access to Link state.
/// Implements FlutterStreamHandler to emit state change events.
class LinkKitBridge: NSObject, FlutterStreamHandler, ABLLinkWrapperDelegate {
    // MARK: - Properties

    private var linkWrapper: ABLLinkWrapper?
    private var _isEnabled: Bool = false
    private var _tempo: Double = 120.0
    private var _quantum: Double = 4.0
    private var _isPlaying: Bool = false
    private var _numPeers: Int = 0

    private var eventSink: FlutterEventSink?
    private let lock = NSLock()

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isEnabled
    }

    var numPeers: Int {
        lock.lock()
        defer { lock.unlock() }
        return _numPeers
    }

    // MARK: - Public API

    /// Enable Ableton Link with specified tempo and quantum
    func enable(tempo: Double, quantum: Double) {
        lock.lock()
        defer { lock.unlock() }

        guard !_isEnabled else {
            print("[LinkKit] Already enabled")
            return
        }

        _tempo = tempo
        _quantum = quantum

        linkWrapper = ABLLinkWrapper(tempo: tempo)
        linkWrapper?.delegate = self
        linkWrapper?.enable(withQuantum: quantum)

        _isEnabled = true

        print("[LinkKit] Enabled: \(tempo)bpm, quantum=\(quantum)")

        // Emit state change
        emitStateUpdate()
    }

    /// Disable Ableton Link
    func disable() {
        lock.lock()
        defer { lock.unlock() }

        guard _isEnabled else {
            return
        }

        linkWrapper?.disable()
        linkWrapper = nil

        _isEnabled = false
        _numPeers = 0

        print("[LinkKit] Disabled")

        // Emit state change
        emitStateUpdate()
    }

    /// Get current Link state
    func getCurrentState() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }

        guard let wrapper = linkWrapper, _isEnabled else {
            return createStateDict()
        }

        let hostTime = wrapper.getCurrentHostTime()
        let tempo = wrapper.getTempo()
        let beat = wrapper.getBeatAtTime(hostTime, quantum: _quantum)
        let phase = wrapper.getPhaseAtTime(hostTime, quantum: _quantum)
        let isPlaying = wrapper.getIsPlaying()

        _tempo = tempo
        _isPlaying = isPlaying

        return createStateDict(
            tempo: tempo,
            beat: beat,
            phase: phase,
            isPlaying: isPlaying
        )
    }

    /// Set tempo (propagates to all peers)
    func setTempo(_ bpm: Double) {
        lock.lock()
        defer { lock.unlock() }

        guard _isEnabled else {
            print("[LinkKit] Cannot set tempo - Link not enabled")
            return
        }

        guard let wrapper = linkWrapper else { return }

        wrapper.setTempo(bpm)
        _tempo = bpm
        print("[LinkKit] Tempo set to \(bpm)bpm")

        emitStateUpdate()
    }

    /// Set transport playing state
    func setIsPlaying(_ playing: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard _isEnabled else {
            print("[LinkKit] Cannot set playing state - Link not enabled")
            return
        }

        guard let wrapper = linkWrapper else { return }

        wrapper.setIsPlaying(playing)
        _isPlaying = playing
        print("[LinkKit] Playing state: \(playing)")

        emitStateUpdate()
    }

    /// Get beat at specific time with quantum
    func getBeatAtTime(_ hostTime: UInt64, quantum: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }

        guard let wrapper = linkWrapper, _isEnabled else {
            return 0.0
        }

        return wrapper.getBeatAtTime(hostTime, quantum: quantum)
    }

    /// Get phase at specific time with quantum
    func getPhaseAtTime(_ hostTime: UInt64, quantum: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }

        guard let wrapper = linkWrapper, _isEnabled else {
            return 0.0
        }

        return wrapper.getPhaseAtTime(hostTime, quantum: quantum)
    }

    /// Get time at which beat occurs
    func getTimeAtBeat(_ beat: Double, quantum: Double) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }

        guard let wrapper = linkWrapper, _isEnabled else {
            return 0
        }

        // Note: ABLLink doesn't have a direct timeAtBeat method
        // We'll need to calculate this based on current state
        let hostTime = wrapper.getCurrentHostTime()
        let currentBeat = wrapper.getBeatAtTime(hostTime, quantum: quantum)
        let tempo = wrapper.getTempo()

        // Calculate time difference for beat difference
        let beatDelta = beat - currentBeat
        let beatsPerSecond = tempo / 60.0
        let secondsDelta = beatDelta / beatsPerSecond

        // Convert to host time units (nanoseconds on iOS)
        let hostTimeDelta = UInt64(secondsDelta * 1_000_000_000)

        return hostTime + hostTimeDelta
    }

    // MARK: - FlutterStreamHandler

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        lock.lock()
        defer { lock.unlock() }

        self.eventSink = events

        // Send initial state
        emitStateUpdate()

        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        lock.lock()
        defer { lock.unlock() }

        self.eventSink = nil
        return nil
    }

    // MARK: - Private Helpers

    private func createStateDict(
        tempo: Double? = nil,
        beat: Double = 0.0,
        phase: Double = 0.0,
        isPlaying: Bool? = nil
    ) -> [String: Any] {
        return [
            "tempo": tempo ?? _tempo,
            "beat": beat,
            "phase": phase,
            "quantum": _quantum,
            "isPlaying": isPlaying ?? _isPlaying,
            "numPeers": _numPeers,
            "hostMicros": Int(Date().timeIntervalSince1970 * 1_000_000)
        ]
    }

    private func emitStateUpdate() {
        guard let sink = eventSink else { return }

        let state = createStateDict()
        DispatchQueue.main.async {
            sink(state)
        }
    }

    // MARK: - ABLLinkWrapperDelegate

    func linkTempoChanged(_ tempo: Double) {
        lock.lock()
        defer { lock.unlock() }

        _tempo = tempo
        emitStateUpdate()
    }

    func linkNumPeersChanged(_ numPeers: Int) {
        lock.lock()
        defer { lock.unlock() }

        _numPeers = numPeers
        print("[LinkKit] Peer count changed: \(numPeers)")
        emitStateUpdate()
    }

    func linkPlayingStateChanged(_ isPlaying: Bool) {
        lock.lock()
        defer { lock.unlock() }

        _isPlaying = isPlaying
        print("[LinkKit] Playing state changed: \(isPlaying)")
        emitStateUpdate()
    }

    // MARK: - Cleanup

    deinit {
        disable()
    }
}
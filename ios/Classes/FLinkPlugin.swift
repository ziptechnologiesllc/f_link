import Flutter
import UIKit

/// Flutter plugin for Ableton Link on iOS using LinkKit framework
///
/// This plugin provides Method Channel communication between Dart and
/// the native LinkKit framework for Ableton Link synchronization on iOS.
///
/// NOTE: Other platforms (Android, Linux, Windows, macOS) use FFI with
/// the C++ Link library. iOS uses this Method Channel approach because
/// LinkKit is an Objective-C/Swift framework.
public class FLinkPlugin: NSObject, FlutterPlugin {
    private var linkBridge: LinkKitBridge?
    private var eventChannel: FlutterEventChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "f_link",
            binaryMessenger: registrar.messenger()
        )

        let eventChannel = FlutterEventChannel(
            name: "f_link/events",
            binaryMessenger: registrar.messenger()
        )

        let instance = FLinkPlugin()
        instance.linkBridge = LinkKitBridge()
        instance.eventChannel = eventChannel

        // Set event stream handler
        eventChannel.setStreamHandler(instance.linkBridge)

        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let bridge = linkBridge else {
            result(FlutterError(
                code: "NOT_INITIALIZED",
                message: "LinkKit bridge not initialized",
                details: nil
            ))
            return
        }

        switch call.method {
        case "enableLink":
            handleEnableLink(call, bridge: bridge, result: result)

        case "disableLink":
            handleDisableLink(bridge: bridge, result: result)

        case "isEnabled":
            result(bridge.isEnabled)

        case "getNumPeers":
            result(bridge.numPeers)

        case "getCurrentState":
            result(bridge.getCurrentState())

        case "setTempo":
            handleSetTempo(call, bridge: bridge, result: result)

        case "setIsPlaying":
            handleSetIsPlaying(call, bridge: bridge, result: result)

        case "getBeatAtTime":
            handleGetBeatAtTime(call, bridge: bridge, result: result)

        case "getPhaseAtTime":
            handleGetPhaseAtTime(call, bridge: bridge, result: result)

        case "getTimeAtBeat":
            handleGetTimeAtBeat(call, bridge: bridge, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Method Handlers

    private func handleEnableLink(
        _ call: FlutterMethodCall,
        bridge: LinkKitBridge,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let tempo = args["tempo"] as? Double,
              let quantum = args["quantum"] as? Double else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "enableLink requires tempo and quantum",
                details: nil
            ))
            return
        }

        bridge.enable(tempo: tempo, quantum: quantum)
        result(nil)
    }

    private func handleDisableLink(
        bridge: LinkKitBridge,
        result: @escaping FlutterResult
    ) {
        bridge.disable()
        result(nil)
    }

    private func handleSetTempo(
        _ call: FlutterMethodCall,
        bridge: LinkKitBridge,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let bpm = args["bpm"] as? Double else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "setTempo requires bpm",
                details: nil
            ))
            return
        }

        bridge.setTempo(bpm)
        result(nil)
    }

    private func handleSetIsPlaying(
        _ call: FlutterMethodCall,
        bridge: LinkKitBridge,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let playing = args["playing"] as? Bool else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "setIsPlaying requires playing boolean",
                details: nil
            ))
            return
        }

        bridge.setIsPlaying(playing)
        result(nil)
    }

    private func handleGetBeatAtTime(
        _ call: FlutterMethodCall,
        bridge: LinkKitBridge,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let hostTime = args["hostTime"] as? Int,
              let quantum = args["quantum"] as? Double else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "getBeatAtTime requires hostTime and quantum",
                details: nil
            ))
            return
        }

        let beat = bridge.getBeatAtTime(UInt64(hostTime), quantum: quantum)
        result(beat)
    }

    private func handleGetPhaseAtTime(
        _ call: FlutterMethodCall,
        bridge: LinkKitBridge,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let hostTime = args["hostTime"] as? Int,
              let quantum = args["quantum"] as? Double else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "getPhaseAtTime requires hostTime and quantum",
                details: nil
            ))
            return
        }

        let phase = bridge.getPhaseAtTime(UInt64(hostTime), quantum: quantum)
        result(phase)
    }

    private func handleGetTimeAtBeat(
        _ call: FlutterMethodCall,
        bridge: LinkKitBridge,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let beat = args["beat"] as? Double,
              let quantum = args["quantum"] as? Double else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "getTimeAtBeat requires beat and quantum",
                details: nil
            ))
            return
        }

        let time = bridge.getTimeAtBeat(beat, quantum: quantum)
        result(Int(time))
    }
}
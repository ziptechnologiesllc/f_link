import 'dart:async';
import 'dart:isolate';
import 'package:flutter/services.dart';

/// Provides Link timing information to isolates on iOS
///
/// Since method channels can't be called directly from isolates,
/// this provider runs in the main isolate and communicates timing
/// data to worker isolates via ports.
class IOSLinkTimingProvider {
  static const MethodChannel _channel = MethodChannel('f_link');
  static IOSLinkTimingProvider? _instance;

  final Map<SendPort, _TimingRequest> _pendingRequests = {};
  Timer? _updateTimer;
  ReceivePort? _receivePort;
  SendPort? _mainSendPort;

  // Cached timing state
  double _tempo = 120.0;
  double _beat = 0.0;
  double _phase = 0.0;
  double _quantum = 4.0;
  bool _isPlaying = false;
  int _lastHostMicros = 0;

  IOSLinkTimingProvider._();

  /// Get singleton instance
  static IOSLinkTimingProvider get instance {
    _instance ??= IOSLinkTimingProvider._();
    return _instance!;
  }

  /// Start the timing provider service
  void start() {
    if (_receivePort != null) return; // Already started

    _receivePort = ReceivePort();
    _mainSendPort = _receivePort!.sendPort;

    // Listen for requests from isolates
    _receivePort!.listen(_handleIsolateRequest);

    // Start periodic updates to keep cache fresh
    _updateTimer = Timer.periodic(Duration(milliseconds: 20), (_) {
      _updateTimingCache();
    });
  }

  /// Stop the timing provider service
  void stop() {
    _updateTimer?.cancel();
    _updateTimer = null;
    _receivePort?.close();
    _receivePort = null;
    _mainSendPort = null;
    _pendingRequests.clear();
  }

  /// Get send port for isolates to communicate with this provider
  SendPort get sendPort {
    if (_mainSendPort == null) {
      throw StateError('IOSLinkTimingProvider not started');
    }
    return _mainSendPort!;
  }

  /// Update cached timing from native side
  Future<void> _updateTimingCache() async {
    try {
      final state = await _channel.invokeMethod<Map<dynamic, dynamic>>('getCurrentState');
      if (state != null) {
        _tempo = (state['tempo'] as num?)?.toDouble() ?? _tempo;
        _beat = (state['beat'] as num?)?.toDouble() ?? _beat;
        _phase = (state['phase'] as num?)?.toDouble() ?? _phase;
        _quantum = (state['quantum'] as num?)?.toDouble() ?? _quantum;
        _isPlaying = state['isPlaying'] as bool? ?? _isPlaying;
        _lastHostMicros = state['hostMicros'] as int? ?? DateTime.now().microsecondsSinceEpoch;
      }
    } catch (e) {
      // Ignore errors, keep using cached values
    }
  }

  /// Handle requests from isolates
  void _handleIsolateRequest(dynamic message) {
    if (message is! Map) return;

    final String? command = message['command'];
    final SendPort? replyPort = message['replyPort'];
    if (command == null || replyPort == null) return;

    switch (command) {
      case 'getBeatAtTime':
        final int hostTime = message['hostTime'] ?? DateTime.now().microsecondsSinceEpoch;
        final double quantum = message['quantum'] ?? 4.0;
        _getBeatAtTime(hostTime, quantum, replyPort);
        break;

      case 'getPhaseAtTime':
        final int hostTime = message['hostTime'] ?? DateTime.now().microsecondsSinceEpoch;
        final double quantum = message['quantum'] ?? 4.0;
        _getPhaseAtTime(hostTime, quantum, replyPort);
        break;

      case 'getState':
        _getState(replyPort);
        break;

      default:
        replyPort.send({'error': 'Unknown command: $command'});
    }
  }

  /// Get beat at time and send to isolate
  Future<void> _getBeatAtTime(int hostTime, double quantum, SendPort replyPort) async {
    try {
      final beat = await _channel.invokeMethod<double>('getBeatAtTime', {
        'hostTime': hostTime,
        'quantum': quantum,
      });
      replyPort.send({'beat': beat ?? _interpolateBeat(hostTime)});
    } catch (e) {
      // Fallback to interpolation
      replyPort.send({'beat': _interpolateBeat(hostTime)});
    }
  }

  /// Get phase at time and send to isolate
  Future<void> _getPhaseAtTime(int hostTime, double quantum, SendPort replyPort) async {
    try {
      final phase = await _channel.invokeMethod<double>('getPhaseAtTime', {
        'hostTime': hostTime,
        'quantum': quantum,
      });
      replyPort.send({'phase': phase ?? _interpolatePhase(hostTime, quantum)});
    } catch (e) {
      // Fallback to interpolation
      replyPort.send({'phase': _interpolatePhase(hostTime, quantum)});
    }
  }

  /// Get current state and send to isolate
  void _getState(SendPort replyPort) {
    replyPort.send({
      'tempo': _tempo,
      'beat': _beat,
      'phase': _phase,
      'quantum': _quantum,
      'isPlaying': _isPlaying,
      'hostMicros': _lastHostMicros,
    });
  }

  /// Interpolate beat based on cached values
  double _interpolateBeat(int hostTime) {
    if (_lastHostMicros > 0 && hostTime > _lastHostMicros) {
      final deltaSeconds = (hostTime - _lastHostMicros) / 1000000.0;
      final beatsPerSecond = _tempo / 60.0;
      final beatDelta = deltaSeconds * beatsPerSecond;
      return _beat + beatDelta;
    }
    return _beat;
  }

  /// Interpolate phase based on cached values
  double _interpolatePhase(int hostTime, double quantum) {
    if (_lastHostMicros > 0 && hostTime > _lastHostMicros) {
      final deltaSeconds = (hostTime - _lastHostMicros) / 1000000.0;
      final beatsPerSecond = _tempo / 60.0;
      final beatDelta = deltaSeconds * beatsPerSecond;

      double newPhase = _phase + beatDelta;
      while (newPhase >= quantum) {
        newPhase -= quantum;
      }
      return newPhase;
    }
    return _phase;
  }
}

/// Timing request from isolate
class _TimingRequest {
  final String command;
  final Map<String, dynamic> params;
  final SendPort replyPort;

  _TimingRequest(this.command, this.params, this.replyPort);
}

/// Client for accessing Link timing from isolates
class IOSLinkTimingClient {
  final SendPort _providerPort;
  final ReceivePort _receivePort = ReceivePort();

  IOSLinkTimingClient(this._providerPort);

  /// Get beat at time
  Future<double> getBeatAtTime(int hostTime, double quantum) async {
    final completer = Completer<double>();

    final subscription = _receivePort.listen((message) {
      if (message is Map && message.containsKey('beat')) {
        completer.complete(message['beat'] as double);
      }
    });

    _providerPort.send({
      'command': 'getBeatAtTime',
      'hostTime': hostTime,
      'quantum': quantum,
      'replyPort': _receivePort.sendPort,
    });

    final result = await completer.future.timeout(
      Duration(milliseconds: 50),
      onTimeout: () => 0.0,
    );

    subscription.cancel();
    return result;
  }

  /// Get phase at time
  Future<double> getPhaseAtTime(int hostTime, double quantum) async {
    final completer = Completer<double>();

    final subscription = _receivePort.listen((message) {
      if (message is Map && message.containsKey('phase')) {
        completer.complete(message['phase'] as double);
      }
    });

    _providerPort.send({
      'command': 'getPhaseAtTime',
      'hostTime': hostTime,
      'quantum': quantum,
      'replyPort': _receivePort.sendPort,
    });

    final result = await completer.future.timeout(
      Duration(milliseconds: 50),
      onTimeout: () => 0.0,
    );

    subscription.cancel();
    return result;
  }

  /// Get current state
  Future<Map<String, dynamic>> getState() async {
    final completer = Completer<Map<String, dynamic>>();

    final subscription = _receivePort.listen((message) {
      if (message is Map && message.containsKey('tempo')) {
        completer.complete(Map<String, dynamic>.from(message));
      }
    });

    _providerPort.send({
      'command': 'getState',
      'replyPort': _receivePort.sendPort,
    });

    final result = await completer.future.timeout(
      Duration(milliseconds: 50),
      onTimeout: () => {
        'tempo': 120.0,
        'beat': 0.0,
        'phase': 0.0,
        'quantum': 4.0,
        'isPlaying': false,
        'hostMicros': DateTime.now().microsecondsSinceEpoch,
      },
    );

    subscription.cancel();
    return result;
  }

  void dispose() {
    _receivePort.close();
  }
}
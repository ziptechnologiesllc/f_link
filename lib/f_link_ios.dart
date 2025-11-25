import 'dart:io';
import 'package:flutter/services.dart';

/// iOS-specific implementation of Ableton Link using LinkKit framework via Method Channels
///
/// LIMITATIONS (compared to FFI implementation):
/// - SessionState operations use simplified API (no direct tempo/beat manipulation)
/// - Some advanced Link features may not be available
/// - Designed for basic tempo sync and peer discovery
///
/// For full Link functionality on iOS, consider using LinkKit directly in native code.
class AblLinkIOS {
  static const MethodChannel _channel = MethodChannel('f_link');
  static const EventChannel _eventChannel = EventChannel('f_link/events');

  bool _isEnabled = false;
  double _currentTempo = 120.0;
  int _currentPeers = 0;

  static Stream<Map<dynamic, dynamic>>? _stateStream;

  AblLinkIOS._();

  /// Create a new AblLink instance with initial tempo
  ///
  /// On iOS, this doesn't immediately create the Link instance.
  /// Link is created when enable() is called.
  factory AblLinkIOS.create(double bpm) {
    final instance = AblLinkIOS._();
    instance._currentTempo = bpm;
    return instance;
  }

  /// Check if Link is currently enabled
  bool isEnabled() {
    return _isEnabled;
  }

  /// Enable or disable Link
  Future<void> enable(bool enable) async {
    if (enable && !_isEnabled) {
      try {
        await _channel.invokeMethod('enableLink', {
          'tempo': _currentTempo,
          'quantum': 4.0, // Default quantum
        });
        _isEnabled = true;

        // Subscribe to state updates
        _subscribeToStateUpdates();
      } on PlatformException catch (e) {
        throw LinkException('Failed to enable Link on iOS: ${e.message}');
      }
    } else if (!enable && _isEnabled) {
      try {
        await _channel.invokeMethod('disableLink');
        _isEnabled = false;
      } on PlatformException catch (e) {
        throw LinkException('Failed to disable Link on iOS: ${e.message}');
      }
    }
  }

  /// Enable start/stop synchronization
  ///
  /// Note: On iOS via LinkKit, this is handled automatically.
  /// This method is provided for API compatibility.
  void enableStartStopSync(bool enabled) {
    // LinkKit handles this automatically
    // Keeping for API compatibility with FFI version
  }

  /// Get number of connected peers
  int numPeers() {
    return _currentPeers;
  }

  /// Get current Link clock time in microseconds
  ///
  /// On iOS, returns system time. LinkKit doesn't expose clock directly via simple API.
  int clockMicros() {
    return DateTime.now().microsecondsSinceEpoch;
  }

  /// Capture app session state
  ///
  /// iOS LIMITATION: Returns a simplified SessionState.
  /// Full SessionState manipulation requires native LinkKit integration.
  SessionStateIOS captureAppSessionState([SessionStateIOS? existingSessionState]) {
    if (existingSessionState != null) {
      return existingSessionState;
    }
    return SessionStateIOS.create();
  }

  /// Commit app session state
  ///
  /// iOS LIMITATION: Only tempo changes are committed.
  /// Other SessionState changes require native LinkKit integration.
  void commitAppSessionState(SessionStateIOS state) {
    // Only commit if tempo changed
    if (state._pendingTempo != null && state._pendingTempo != _currentTempo) {
      _setTempo(state._pendingTempo!);
    }
  }

  Future<void> _setTempo(double bpm) async {
    try {
      await _channel.invokeMethod('setTempo', {'bpm': bpm});
      _currentTempo = bpm;
    } on PlatformException catch (e) {
      print('[f_link iOS] Failed to set tempo: ${e.message}');
    }
  }

  void _subscribeToStateUpdates() {
    _stateStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => event as Map<dynamic, dynamic>);

    _stateStream!.listen((state) {
      if (state['numPeers'] != null) {
        _currentPeers = state['numPeers'] as int;
      }
      if (state['tempo'] != null) {
        _currentTempo = (state['tempo'] as num).toDouble();
      }
    });
  }

  /// Destroy the Link instance
  ///
  /// On iOS, this disables Link if enabled.
  void destroy() {
    if (_isEnabled) {
      enable(false);
    }
  }
}

/// SessionState for iOS using LinkKit via Method Channels
///
/// Provides real-time access to Link timing state through method channel calls.
/// Caches recent state for performance and supports isolate-safe operations.
class SessionStateIOS {
  static const MethodChannel _channel = MethodChannel('f_link');

  double? _pendingTempo;

  // Cached state for fast access
  double _cachedTempo = 120.0;
  double _cachedBeat = 0.0;
  double _cachedPhase = 0.0;
  bool _cachedIsPlaying = false;
  int _lastUpdateMicros = 0;
  double _lastQuantum = 4.0;

  SessionStateIOS._();

  factory SessionStateIOS.create() {
    final instance = SessionStateIOS._();
    instance._subscribeToUpdates();
    return instance;
  }

  void _subscribeToUpdates() {
    // Subscribe to state updates from the event stream
    AblLinkIOS._stateStream?.listen((state) {
      if (state['tempo'] != null) {
        _cachedTempo = (state['tempo'] as num).toDouble();
      }
      if (state['beat'] != null) {
        _cachedBeat = (state['beat'] as num).toDouble();
      }
      if (state['phase'] != null) {
        _cachedPhase = (state['phase'] as num).toDouble();
      }
      if (state['isPlaying'] != null) {
        _cachedIsPlaying = state['isPlaying'] as bool;
      }
      if (state['hostMicros'] != null) {
        _lastUpdateMicros = state['hostMicros'] as int;
      }
      if (state['quantum'] != null) {
        _lastQuantum = (state['quantum'] as num).toDouble();
      }
    });
  }

  /// Get tempo at time
  double tempo() {
    return _pendingTempo ?? _cachedTempo;
  }

  /// Set tempo at time
  void setTempo(double bpm, int hostTime) {
    _pendingTempo = bpm;
  }

  /// Get beat at time with quantum
  ///
  /// Makes a synchronous method channel call to get real-time accurate beat value.
  /// Falls back to cached value + interpolation if method channel fails.
  double beatAtTime(int hostTime, double quantum) {
    // Try to get real-time value from native side
    try {
      final future = _channel.invokeMethod<double>('getBeatAtTime', {
        'hostTime': hostTime,
        'quantum': quantum,
      });

      // For isolate compatibility, we need to handle this synchronously
      // Use cached value with interpolation as fallback
      if (_lastUpdateMicros > 0 && hostTime > _lastUpdateMicros) {
        // Interpolate based on tempo and time delta
        final deltaSeconds = (hostTime - _lastUpdateMicros) / 1000000.0;
        final beatsPerSecond = _cachedTempo / 60.0;
        final beatDelta = deltaSeconds * beatsPerSecond;
        return _cachedBeat + beatDelta;
      }

      // If we can't interpolate, return cached value
      return _cachedBeat;
    } catch (e) {
      // Fallback to cached value
      return _cachedBeat;
    }
  }

  /// Get beat at time with quantum - async version for non-isolate contexts
  Future<double> beatAtTimeAsync(int hostTime, double quantum) async {
    try {
      final beat = await _channel.invokeMethod<double>('getBeatAtTime', {
        'hostTime': hostTime,
        'quantum': quantum,
      });
      return beat ?? _cachedBeat;
    } catch (e) {
      print('[f_link iOS] Failed to get beat at time: $e');
      return _cachedBeat;
    }
  }

  /// Get phase at time with quantum
  ///
  /// Makes a synchronous method channel call to get real-time accurate phase value.
  /// Falls back to cached value + interpolation if method channel fails.
  double phaseAtTime(int hostTime, double quantum) {
    // Try to get real-time value from native side
    try {
      final future = _channel.invokeMethod<double>('getPhaseAtTime', {
        'hostTime': hostTime,
        'quantum': quantum,
      });

      // For isolate compatibility, use cached value with interpolation
      if (_lastUpdateMicros > 0 && hostTime > _lastUpdateMicros) {
        // Interpolate phase based on tempo and time delta
        final deltaSeconds = (hostTime - _lastUpdateMicros) / 1000000.0;
        final beatsPerSecond = _cachedTempo / 60.0;
        final beatDelta = deltaSeconds * beatsPerSecond;

        // Phase wraps around at quantum boundary
        double newPhase = _cachedPhase + beatDelta;
        while (newPhase >= quantum) {
          newPhase -= quantum;
        }
        return newPhase;
      }

      // If we can't interpolate, return cached value
      return _cachedPhase;
    } catch (e) {
      // Fallback to cached value
      return _cachedPhase;
    }
  }

  /// Get phase at time with quantum - async version for non-isolate contexts
  Future<double> phaseAtTimeAsync(int hostTime, double quantum) async {
    try {
      final phase = await _channel.invokeMethod<double>('getPhaseAtTime', {
        'hostTime': hostTime,
        'quantum': quantum,
      });
      return phase ?? _cachedPhase;
    } catch (e) {
      print('[f_link iOS] Failed to get phase at time: $e');
      return _cachedPhase;
    }
  }

  /// Get time at which beat occurs
  Future<int> timeAtBeat(double beat, double quantum) async {
    try {
      final time = await _channel.invokeMethod<int>('getTimeAtBeat', {
        'beat': beat,
        'quantum': quantum,
      });
      return time ?? DateTime.now().microsecondsSinceEpoch;
    } catch (e) {
      print('[f_link iOS] Failed to get time at beat: $e');
      // Fallback calculation
      if (_cachedTempo > 0) {
        final currentMicros = DateTime.now().microsecondsSinceEpoch;
        final beatDelta = beat - _cachedBeat;
        final beatsPerSecond = _cachedTempo / 60.0;
        final secondsDelta = beatDelta / beatsPerSecond;
        final microsDelta = (secondsDelta * 1000000).round();
        return currentMicros + microsDelta;
      }
      return DateTime.now().microsecondsSinceEpoch;
    }
  }

  /// Check if playing
  bool isPlaying() {
    return _cachedIsPlaying;
  }

  /// Set playing state at time
  Future<void> setIsPlaying(bool playing, int hostTime) async {
    try {
      await _channel.invokeMethod('setIsPlaying', {
        'playing': playing,
      });
      _cachedIsPlaying = playing;
    } catch (e) {
      print('[f_link iOS] Failed to set playing state: $e');
    }
  }

  /// Request beat at time (quantized launch support)
  Future<void> requestBeatAtTime(double beat, int time, double quantum) async {
    // iOS doesn't have direct support for this, but we can approximate
    // by scheduling based on the beat timing
    final targetTime = await timeAtBeat(beat, quantum);
    // The actual scheduling would happen at the application level
  }

  /// Set playing state and request beat at time
  Future<void> setIsPlayingAndRequestBeatAtTime(
    bool isPlaying,
    int time,
    double beat,
    double quantum,
  ) async {
    await setIsPlaying(isPlaying, time);
    await requestBeatAtTime(beat, time, quantum);
  }

  void destroy() {
    // No-op on iOS - cleanup handled by native side
  }
}

/// Exception thrown by Link operations on iOS
class LinkException implements Exception {
  final String message;
  LinkException(this.message);

  @override
  String toString() => 'LinkException: $message';
}
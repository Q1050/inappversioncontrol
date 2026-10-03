import 'dart:async';

import 'package:flutter/widgets.dart';

import 'client.dart';
import 'models.dart';

/// Coordinates version checks with the Flutter application lifecycle.
///
/// Call [start] once and [dispose] when the owning component is disposed.
/// Existing users of [InAppVersionControl] are unaffected unless they create
/// this coordinator.
class VersionControlLifecycle extends ChangeNotifier
    with WidgetsBindingObserver {
  /// The checker used for each policy evaluation.
  final InAppVersionControl versionControl;

  /// The identifier passed to the configured provider.
  final String appId;

  /// The installed app version to compare with remote rules.
  final String currentVersion;

  /// The platform to check, or `null` to use the current platform.
  final AppPlatform? platform;

  /// The environment to check, or `null` to use the checker's default.
  final AppEnvironment? environment;

  /// Whether [start] performs an initial check.
  final bool checkInitially;

  /// Whether returning from the background requests another check.
  final bool checkOnResume;

  UpdateDecision? _decision;
  Object? _error;
  StackTrace? _errorStackTrace;
  bool _isChecking = false;
  bool _hasDepartedForeground = false;
  bool _pendingCheck = false;
  bool _started = false;
  bool _disposed = false;
  Future<void>? _activeCheck;

  /// Creates an optional lifecycle coordinator for version checks.
  VersionControlLifecycle({
    required this.versionControl,
    required this.appId,
    required this.currentVersion,
    this.platform,
    this.environment,
    this.checkInitially = true,
    this.checkOnResume = true,
  });

  /// The last successful decision, or `null` before the first success.
  UpdateDecision? get decision => _decision;

  /// The most recent check error, or `null` after a successful check.
  Object? get error => _error;

  /// The stack trace associated with [error].
  StackTrace? get errorStackTrace => _errorStackTrace;

  /// Whether a check is currently running.
  bool get isChecking => _isChecking;

  /// Whether [start] has registered this lifecycle observer.
  bool get isStarted => _started;

  /// Registers the lifecycle observer and optionally performs the initial check.
  /// Repeated calls are safe and do not perform another initial check.
  Future<void> start() {
    if (_disposed) {
      throw StateError('Cannot start a disposed VersionControlLifecycle.');
    }
    if (_started) {
      return _activeCheck ?? Future<void>.value();
    }

    _started = true;
    WidgetsBinding.instance.addObserver(this);
    return checkInitially ? refresh() : Future<void>.value();
  }

  /// Requests a policy evaluation.
  ///
  /// If a check is running, requests are coalesced into one pending check that
  /// runs after the active check finishes.
  Future<void> refresh() {
    if (_disposed) {
      return Future<void>.value();
    }
    if (_isChecking) {
      _pendingCheck = true;
      return _activeCheck ?? Future<void>.value();
    }

    _isChecking = true;
    final completer = Completer<void>();
    _activeCheck = completer.future;
    _notifyListeners();
    unawaited(_runChecks(completer));
    return completer.future;
  }

  Future<void> _runChecks(Completer<void> completer) async {
    try {
      do {
        _pendingCheck = false;
        try {
          final nextDecision = await versionControl.check(
            appId: appId,
            platform: platform,
            environment: environment,
            currentVersion: currentVersion,
          );
          if (_disposed) break;
          _decision = nextDecision;
          _error = null;
          _errorStackTrace = null;
        } on Object catch (error, stackTrace) {
          if (_disposed) break;
          // Keep the last authoritative decision, especially blocking states.
          _error = error;
          _errorStackTrace = stackTrace;
        }
        _notifyListeners();
      } while (_pendingCheck && !_disposed);
    } finally {
      _isChecking = false;
      _activeCheck = null;
      _notifyListeners();
      completer.complete();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started || _disposed || !checkOnResume) return;

    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _hasDepartedForeground = true;
        break;
      case AppLifecycleState.resumed:
        if (!_hasDepartedForeground) return;
        _hasDepartedForeground = false;
        unawaited(refresh());
        break;
      case AppLifecycleState.inactive:
        // Inactive can be a temporary focus interruption, not a departure.
        break;
    }
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _pendingCheck = false;
    super.dispose();
  }
}

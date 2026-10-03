import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_version_control/in_app_version_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ControllableProvider provider;
  late VersionControlLifecycle lifecycle;

  setUp(() {
    provider = _ControllableProvider();
    lifecycle = VersionControlLifecycle(
      versionControl: InAppVersionControl(provider: provider),
      appId: 'com.example.app',
      platform: AppPlatform.android,
      currentVersion: '1.0.0',
    );
  });

  tearDown(() {
    lifecycle.dispose();
  });

  testWidgets('initial evaluation occurs exactly once', (tester) async {
    await lifecycle.start();

    expect(provider.checkCount, 1);
    expect(lifecycle.decision?.type, UpdateType.none);
  });

  testWidgets('initial and repeated resumed notifications do not recheck', (
    tester,
  ) async {
    await lifecycle.start();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(provider.checkCount, 1);
  });

  testWidgets('one genuine departure produces one resume recheck', (
    tester,
  ) async {
    await lifecycle.start();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(provider.checkCount, 2);
  });

  testWidgets('inactive alone is not a genuine foreground departure', (
    tester,
  ) async {
    await lifecycle.start();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(provider.checkCount, 1);
  });

  testWidgets('separate resume cycles each produce one recheck', (
    tester,
  ) async {
    await lifecycle.start();

    for (var i = 0; i < 2; i++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }

    expect(provider.checkCount, 3);
  });

  testWidgets('widget rebuilds do not request policy checks', (tester) async {
    await lifecycle.start();

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('first'),
      ),
    );
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('second'),
      ),
    );

    expect(provider.checkCount, 1);
  });

  testWidgets('checks never overlap and resume requests are coalesced', (
    tester,
  ) async {
    final firstCheck = Completer<VersionRule>();
    provider.enqueue(() => firstCheck.future);

    final start = lifecycle.start();
    expect(provider.activeChecks, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(provider.checkCount, 1);
    expect(provider.maxActiveChecks, 1);

    firstCheck.complete(_allowedRule);
    await start;

    expect(provider.checkCount, 2);
    expect(provider.maxActiveChecks, 1);
  });

  testWidgets('disposal unregisters lifecycle handling', (tester) async {
    await lifecycle.start();
    lifecycle.dispose();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(provider.checkCount, 1);
  });

  testWidgets('known force decision survives a refresh failure', (
    tester,
  ) async {
    provider.enqueue(() async => _forceRule);
    await lifecycle.start();
    expect(lifecycle.decision?.type, UpdateType.force);

    provider.enqueue(() async => throw StateError('offline'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(lifecycle.decision?.type, UpdateType.force);
    expect(lifecycle.error, isA<StateError>());
  });

  testWidgets('known maintenance decision survives a refresh failure', (
    tester,
  ) async {
    provider.enqueue(() async => _maintenanceRule);
    await lifecycle.start();

    provider.enqueue(() async => throw StateError('offline'));
    await lifecycle.refresh();

    expect(lifecycle.decision?.type, UpdateType.maintenance);
    expect(lifecycle.error, isA<StateError>());
  });

  testWidgets('cold-start failure has no decision and exposes the error', (
    tester,
  ) async {
    provider.enqueue(() async => throw StateError('offline'));

    await lifecycle.start();

    expect(lifecycle.decision, isNull);
    expect(lifecycle.error, isA<StateError>());
  });
}

const _allowedRule = VersionRule(minVersion: '1.0.0', latestVersion: '1.0.0');

const _forceRule = VersionRule(minVersion: '2.0.0', latestVersion: '2.0.0');

const _maintenanceRule = VersionRule(
  minVersion: '1.0.0',
  latestVersion: '1.0.0',
  maintenance: true,
);

class _ControllableProvider implements VersionRuleProvider {
  final List<Future<VersionRule> Function()> _queuedRules = [];
  int checkCount = 0;
  int activeChecks = 0;
  int maxActiveChecks = 0;

  @override
  BackendService get backendService => BackendService.custom;

  void enqueue(Future<VersionRule> Function() rule) {
    _queuedRules.add(rule);
  }

  @override
  Future<VersionRule> fetchRule({
    required String appId,
    required AppPlatform platform,
  }) async {
    checkCount++;
    activeChecks++;
    if (activeChecks > maxActiveChecks) maxActiveChecks = activeChecks;
    try {
      if (_queuedRules.isEmpty) return _allowedRule;
      return await _queuedRules.removeAt(0)();
    } finally {
      activeChecks--;
    }
  }
}

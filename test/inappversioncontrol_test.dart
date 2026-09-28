import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_version_control/in_app_version_control.dart';

class FakeProvider implements VersionRuleProvider {
  final VersionRule rule;
  final BackendService service;
  AppPlatform? lastPlatform;

  FakeProvider(this.rule, {this.service = BackendService.custom});

  @override
  BackendService get backendService => service;

  @override
  Future<VersionRule> fetchRule({
    required String appId,
    required AppPlatform platform,
  }) async {
    lastPlatform = platform;
    return rule;
  }
}

class EnvironmentFakeProvider implements EnvironmentVersionRuleProvider {
  AppEnvironment? lastEnvironment;

  @override
  BackendService get backendService => BackendService.custom;

  @override
  Future<VersionRule> fetchRule({
    required String appId,
    required AppPlatform platform,
  }) => fetchRuleForEnvironment(
    appId: appId,
    platform: platform,
    environment: AppEnvironment.production,
  );

  @override
  Future<VersionRule> fetchRuleForEnvironment({
    required String appId,
    required AppPlatform platform,
    required AppEnvironment environment,
  }) async {
    lastEnvironment = environment;
    return const VersionRule(minVersion: '1.0.0', latestVersion: '1.0.0');
  }
}

void main() {
  test('returns optional update when behind latest but above min', () async {
    final vc = InAppVersionControl(
      provider: FakeProvider(
        const VersionRule(
          minVersion: '1.0.0',
          latestVersion: '1.2.0',
          storeUrl: 'https://example.com',
          message: 'Update available',
        ),
      ),
    );
    final decision = await vc.check(
      appId: 'com.example.app',
      platform: AppPlatform.android,
      currentVersion: '1.1.0',
    );
    expect(decision.type, UpdateType.optional);
  });

  test('returns force update when below min version', () async {
    final vc = InAppVersionControl(
      provider: FakeProvider(
        const VersionRule(
          minVersion: '1.0.0',
          latestVersion: '1.2.0',
          storeUrl: 'https://example.com',
          message: 'Update available',
        ),
      ),
    );
    final decision = await vc.check(
      appId: 'com.example.app',
      platform: AppPlatform.android,
      currentVersion: '0.9.0',
    );
    expect(decision.type, UpdateType.force);
  });

  test('returns none when current version matches latest', () async {
    final vc = InAppVersionControl(
      provider: FakeProvider(
        const VersionRule(minVersion: '1.0.0', latestVersion: '1.2.0'),
      ),
    );

    final decision = await vc.check(
      appId: 'com.example.app',
      platform: AppPlatform.android,
      currentVersion: '1.2.0',
    );

    expect(decision.type, UpdateType.none);
    expect(decision.requiresAction, isFalse);
  });

  test('returns maintenance when maintenance mode is enabled', () async {
    final vc = InAppVersionControl(
      provider: FakeProvider(
        const VersionRule(
          minVersion: '1.0.0',
          latestVersion: '1.2.0',
          maintenance: true,
          message: 'Scheduled maintenance',
        ),
      ),
    );

    final decision = await vc.check(
      appId: 'com.example.app',
      platform: AppPlatform.ios,
      currentVersion: '9.9.9',
    );

    expect(decision.type, UpdateType.maintenance);
    expect(decision.message, 'Scheduled maintenance');
  });

  test('compares versions with different segment lengths', () {
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('1.2.1', '1.2'), greaterThan(0));
  });

  test('throws for invalid version strings', () {
    expect(() => compareVersions('1.0.0-beta', '1.0.0'), throwsFormatException);
  });

  test('exposes backend service from the provider', () {
    final provider = FakeProvider(
      const VersionRule(minVersion: '1.0.0', latestVersion: '1.2.0'),
      service: BackendService.firebase,
    );

    final versionControl = InAppVersionControl(provider: provider);

    expect(versionControl.backendService, BackendService.firebase);
  });

  test('defaults to the current platform when none is passed', () async {
    final provider = FakeProvider(
      const VersionRule(minVersion: '1.0.0', latestVersion: '1.2.0'),
    );

    await InAppVersionControl(
      provider: provider,
    ).check(appId: 'com.example.app', currentVersion: '1.2.0');

    expect(provider.lastPlatform, AppPlatform.current);
  });

  test(
    'uses production by default and allows an environment override',
    () async {
      final provider = EnvironmentFakeProvider();
      final versionControl = InAppVersionControl(provider: provider);

      await versionControl.check(
        appId: 'com.example.app',
        platform: AppPlatform.android,
        currentVersion: '1.0.0',
      );
      expect(provider.lastEnvironment, AppEnvironment.production);

      await versionControl.check(
        appId: 'com.example.app',
        platform: AppPlatform.android,
        environment: AppEnvironment.development,
        currentVersion: '1.0.0',
      );
      expect(provider.lastEnvironment, AppEnvironment.development);
    },
  );

  test('throws when the rule disallows the requested platform', () async {
    final versionControl = InAppVersionControl(
      provider: FakeProvider(
        const VersionRule(
          minVersion: '1.0.0',
          latestVersion: '1.2.0',
          supportedPlatforms: {AppPlatform.ios},
        ),
      ),
    );

    expect(
      () => versionControl.check(
        appId: 'com.example.app',
        platform: AppPlatform.android,
        currentVersion: '1.0.0',
      ),
      throwsA(isA<UnsupportedAppPlatformException>()),
    );
  });

  test('endpoint provider identifies itself as a custom backend', () {
    final provider = EndpointVersionRuleProvider(
      endpoint: Uri.parse('https://example.com/rule'),
    );
    addTearDown(provider.close);

    expect(provider.backendService, BackendService.custom);
  });

  test(
    'endpoint provider maps the default contract from a custom backend',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        expect(request.uri.queryParameters['appId'], 'com.example.app');
        expect(request.uri.queryParameters['platform'], 'android');

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'minVersion': '1.0.0',
              'latestVersion': '1.2.0',
              'storeUrl': 'https://example.com/store',
              'message': 'Upgrade now',
              'maintenance': false,
            }),
          );
        await request.response.close();
      });

      final provider = EndpointVersionRuleProvider(
        endpoint: Uri.parse(
          'http://${server.address.host}:${server.port}/rule',
        ),
      );
      addTearDown(provider.close);

      final decision = await InAppVersionControl(provider: provider).check(
        appId: 'com.example.app',
        platform: AppPlatform.android,
        currentVersion: '0.9.0',
      );

      expect(decision.type, UpdateType.force);
      expect(decision.storeUrl, 'https://example.com/store');
    },
  );

  test(
    'endpoint provider supports custom response mapping for existing APIs',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final payload = jsonDecode(body) as Map<String, dynamic>;

        expect(payload['appId'], 'com.example.app');
        expect(payload['platform'], 'ios');

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'data': {
                'minimum_supported': '1.0.0',
                'latest_available': '1.1.0',
                'upgrade_url': 'https://example.com/ios',
                'notice': 'Minor improvements',
                'maintenance_mode': false,
              },
            }),
          );
        await request.response.close();
      });

      final provider = EndpointVersionRuleProvider(
        endpoint: Uri.parse(
          'http://${server.address.host}:${server.port}/rule',
        ),
        method: EndpointRequestMethod.post,
        ruleBuilder: (json, context) {
          final data = json['data'] as Map<String, dynamic>;
          return VersionRule(
            minVersion: data['minimum_supported'] as String,
            latestVersion: data['latest_available'] as String,
            storeUrl: data['upgrade_url'] as String?,
            message: data['notice'] as String?,
            maintenance: data['maintenance_mode'] as bool? ?? false,
          );
        },
      );
      addTearDown(provider.close);

      final decision = await InAppVersionControl(provider: provider).check(
        appId: 'com.example.app',
        platform: AppPlatform.ios,
        currentVersion: '1.0.5',
      );

      expect(decision.type, UpdateType.optional);
      expect(decision.message, 'Minor improvements');
    },
  );
}

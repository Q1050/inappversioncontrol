import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_version_control/in_app_version_control.dart';

void main() {
  test('firebase provider identifies itself as a firebase backend', () {
    final provider = FirebaseVersionRuleProvider.remoteConfigClient(
      remoteConfigClient: _FakeRemoteConfigClient(
        values: {
          'version_rule_android':
              '{"minVersion":"1.0.0","latestVersion":"1.2.0"}',
        },
      ),
      keys: const {AppPlatform.android: 'version_rule_android'},
      shouldFetchAndActivate: false,
    );

    expect(provider.backendService, BackendService.firebase);
  });

  test('firebase provider fetches and parses a platform-specific rule', () async {
    final provider = FirebaseVersionRuleProvider.remoteConfigClient(
      remoteConfigClient: _FakeRemoteConfigClient(
        values: {
          'version_rule_android':
              '{"minVersion":"1.0.0","latestVersion":"1.2.0","maintenance":false}',
        },
      ),
      keys: const {AppPlatform.android: 'version_rule_android'},
      shouldFetchAndActivate: false,
    );

    final rule = await provider.fetchRule(
      appId: 'com.example.app',
      platform: AppPlatform.android,
    );

    expect(rule.minVersion, '1.0.0');
    expect(rule.latestVersion, '1.2.0');
    expect(rule.maintenance, isFalse);
  });

  test('firebase provider falls back to the default key', () async {
    final provider = FirebaseVersionRuleProvider.remoteConfigClient(
      remoteConfigClient: _FakeRemoteConfigClient(
        values: {
          'shared_rule':
              '{"minVersion":"2.0.0","latestVersion":"2.1.0","supportedPlatforms":["android","ios"]}',
        },
      ),
      defaultKey: 'shared_rule',
      shouldFetchAndActivate: false,
    );

    final rule = await provider.fetchRule(
      appId: 'com.example.app',
      platform: AppPlatform.ios,
    );

    expect(rule.supportedPlatforms, {AppPlatform.android, AppPlatform.ios});
  });

  test('firebase provider throws when the configured key is missing', () async {
    final provider = FirebaseVersionRuleProvider.remoteConfigClient(
      remoteConfigClient: const _FakeRemoteConfigClient(values: {}),
      keys: const {AppPlatform.android: 'missing_key'},
      shouldFetchAndActivate: false,
    );

    expect(
      () => provider.fetchRule(
        appId: 'com.example.app',
        platform: AppPlatform.android,
      ),
      throwsA(isA<FirebaseVersionRuleException>()),
    );
  });

  test('firebase provider selects a key by environment and platform', () async {
    final provider = FirebaseVersionRuleProvider.remoteConfigClient(
      remoteConfigClient: const _FakeRemoteConfigClient(
        values: {
          'version_rule_android_testing':
              '{"minVersion":"3.0.0","latestVersion":"3.1.0"}',
        },
      ),
      environmentKeys: const {
        AppEnvironment.testing: {
          AppPlatform.android: 'version_rule_android_testing',
        },
      },
      shouldFetchAndActivate: false,
    );

    final rule = await provider.fetchRuleForEnvironment(
      appId: 'com.example.app',
      platform: AppPlatform.android,
      environment: AppEnvironment.testing,
    );

    expect(rule.minVersion, '3.0.0');
  });
}

class _FakeRemoteConfigClient implements FirebaseRemoteConfigClient {
  final Map<String, String> values;

  const _FakeRemoteConfigClient({required this.values});

  @override
  Future<bool> fetchAndActivate() async => true;

  @override
  String getString(String key) => values[key] ?? '';
}

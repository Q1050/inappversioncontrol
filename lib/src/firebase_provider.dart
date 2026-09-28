import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';

import 'models.dart';
import 'provider.dart';

class FirebaseVersionRuleProvider implements EnvironmentVersionRuleProvider {
  final FirebaseRemoteConfigClient _remoteConfig;
  final Map<AppPlatform, String> keys;
  final Map<AppEnvironment, Map<AppPlatform, String>> environmentKeys;
  final String? defaultKey;
  final bool shouldFetchAndActivate;

  FirebaseVersionRuleProvider.remoteConfig({
    FirebaseRemoteConfig? remoteConfig,
    Map<AppPlatform, String> keys = const {},
    Map<AppEnvironment, Map<AppPlatform, String>> environmentKeys = const {},
    this.defaultKey,
    this.shouldFetchAndActivate = true,
  }) : assert(
         keys.isNotEmpty || environmentKeys.isNotEmpty || defaultKey != null,
         'Provide platform keys, environment keys, or a defaultKey.',
       ),
       keys = Map.unmodifiable(keys),
       environmentKeys = _freezeEnvironmentKeys(environmentKeys),
       _remoteConfig = _FirebaseRemoteConfigClient(
         remoteConfig ?? FirebaseRemoteConfig.instance,
       );

  FirebaseVersionRuleProvider.remoteConfigClient({
    required FirebaseRemoteConfigClient remoteConfigClient,
    Map<AppPlatform, String> keys = const {},
    Map<AppEnvironment, Map<AppPlatform, String>> environmentKeys = const {},
    this.defaultKey,
    this.shouldFetchAndActivate = true,
  }) : assert(
         keys.isNotEmpty || environmentKeys.isNotEmpty || defaultKey != null,
         'Provide platform keys, environment keys, or a defaultKey.',
       ),
       keys = Map.unmodifiable(keys),
       environmentKeys = _freezeEnvironmentKeys(environmentKeys),
       _remoteConfig = remoteConfigClient;

  @override
  BackendService get backendService => BackendService.firebase;

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
    if (shouldFetchAndActivate) {
      await _remoteConfig.fetchAndActivate();
    }

    final key =
        environmentKeys[environment]?[platform] ?? keys[platform] ?? defaultKey;
    if (key == null) {
      throw FirebaseVersionRuleException(
        'No Remote Config key configured for platform ${platform.value}.',
      );
    }

    final raw = _remoteConfig.getString(key).trim();
    if (raw.isEmpty) {
      throw FirebaseVersionRuleException(
        'Remote Config key "$key" returned an empty value.',
      );
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw FirebaseVersionRuleException(
        'Remote Config key "$key" must contain a JSON object.',
      );
    }

    try {
      return VersionRule.fromJson(decoded);
    } on Object catch (error) {
      throw FirebaseVersionRuleException(
        'Failed to parse Firebase version rule from key "$key": $error',
      );
    }
  }
}

Map<AppEnvironment, Map<AppPlatform, String>> _freezeEnvironmentKeys(
  Map<AppEnvironment, Map<AppPlatform, String>> keys,
) => Map.unmodifiable(
  keys.map(
    (environment, platformKeys) => MapEntry(
      environment,
      Map<AppPlatform, String>.unmodifiable(platformKeys),
    ),
  ),
);

class FirebaseVersionRuleException implements Exception {
  final String message;

  const FirebaseVersionRuleException(this.message);

  @override
  String toString() => 'FirebaseVersionRuleException: $message';
}

abstract class FirebaseRemoteConfigClient {
  Future<bool> fetchAndActivate();

  String getString(String key);
}

class _FirebaseRemoteConfigClient implements FirebaseRemoteConfigClient {
  final FirebaseRemoteConfig remoteConfig;

  const _FirebaseRemoteConfigClient(this.remoteConfig);

  @override
  Future<bool> fetchAndActivate() => remoteConfig.fetchAndActivate();

  @override
  String getString(String key) => remoteConfig.getString(key);
}

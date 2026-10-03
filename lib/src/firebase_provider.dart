import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';

import 'models.dart';
import 'provider.dart';

/// Loads version rules from Firebase Remote Config.
class FirebaseVersionRuleProvider implements EnvironmentVersionRuleProvider {
  final FirebaseRemoteConfigClient _remoteConfig;

  /// Remote Config keys selected by platform.
  final Map<AppPlatform, String> keys;

  /// Remote Config keys selected by environment and platform.
  final Map<AppEnvironment, Map<AppPlatform, String>> environmentKeys;

  /// The fallback key used when no environment or platform key matches.
  final String? defaultKey;

  /// Whether Remote Config should fetch and activate before reading a value.
  final bool shouldFetchAndActivate;

  /// Creates a provider using the Firebase Remote Config plugin.
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

  /// Creates a provider using a custom Remote Config client.
  ///
  /// This constructor is useful for tests or custom Firebase wrappers.
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

/// Thrown when Firebase does not contain a usable version rule.
class FirebaseVersionRuleException implements Exception {
  /// A description of the Firebase configuration or parsing failure.
  final String message;

  /// Creates a Firebase version-rule exception with [message].
  const FirebaseVersionRuleException(this.message);

  @override
  String toString() => 'FirebaseVersionRuleException: $message';
}

/// The Remote Config operations required by [FirebaseVersionRuleProvider].
abstract class FirebaseRemoteConfigClient {
  /// Fetches the latest Remote Config values and activates them.
  Future<bool> fetchAndActivate();

  /// Returns the string stored under [key].
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

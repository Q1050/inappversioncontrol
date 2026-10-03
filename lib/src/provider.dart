import 'models.dart';

/// A backend adapter that supplies version rules.
abstract class VersionRuleProvider {
  /// Identifies the service that supplies this provider's rules.
  BackendService get backendService;

  /// Loads the version rule for [appId] on [platform].
  Future<VersionRule> fetchRule({
    required String appId,
    required AppPlatform platform,
  });
}

/// Optional provider contract for backends that store separate rules per
/// deployment environment.
abstract class EnvironmentVersionRuleProvider implements VersionRuleProvider {
  /// Loads the version rule for an app, platform, and deployment environment.
  Future<VersionRule> fetchRuleForEnvironment({
    required String appId,
    required AppPlatform platform,
    required AppEnvironment environment,
  });
}

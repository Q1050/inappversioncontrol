import 'models.dart';

/// A backend adapter (Firebase, Supabase, REST, etc.)
abstract class VersionRuleProvider {
  BackendService get backendService;

  /// Example: [appId] = `com.company.app`, [platform] = [AppPlatform.android].
  Future<VersionRule> fetchRule({
    required String appId,
    required AppPlatform platform,
  });
}

/// Optional provider contract for backends that store separate rules per
/// deployment environment.
abstract class EnvironmentVersionRuleProvider implements VersionRuleProvider {
  Future<VersionRule> fetchRuleForEnvironment({
    required String appId,
    required AppPlatform platform,
    required AppEnvironment environment,
  });
}

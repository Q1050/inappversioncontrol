import 'models.dart';
import 'provider.dart';
import 'version_compare.dart';

class InAppVersionControl {
  final VersionRuleProvider provider;
  final AppEnvironment environment;

  const InAppVersionControl({
    required this.provider,
    this.environment = AppEnvironment.production,
  });

  BackendService get backendService => provider.backendService;

  Future<UpdateDecision> check({
    required String appId,
    AppPlatform? platform,
    AppEnvironment? environment,
    required String currentVersion,
  }) async {
    final resolvedPlatform = platform ?? AppPlatform.current;
    final resolvedEnvironment = environment ?? this.environment;
    final rule = provider is EnvironmentVersionRuleProvider
        ? await (provider as EnvironmentVersionRuleProvider)
              .fetchRuleForEnvironment(
                appId: appId,
                platform: resolvedPlatform,
                environment: resolvedEnvironment,
              )
        : await provider.fetchRule(appId: appId, platform: resolvedPlatform);

    if (!rule.supportsPlatform(resolvedPlatform)) {
      throw UnsupportedAppPlatformException(
        platform: resolvedPlatform,
        supportedPlatforms: rule.supportedPlatforms!,
      );
    }

    // Maintenance overrides everything, so if maintenance is true, we return that immediately
    if (rule.maintenance) {
      return UpdateDecision.maintenance(
        currentVersion: currentVersion,
        minVersion: rule.minVersion,
        latestVersion: rule.latestVersion,
        message: rule.message,
      );
    }

    // If current < min => force update
    if (compareVersions(currentVersion, rule.minVersion) < 0) {
      return UpdateDecision.force(
        currentVersion: currentVersion,
        minVersion: rule.minVersion,
        latestVersion: rule.latestVersion,
        storeUrl: rule.storeUrl,
        message: rule.message,
      );
    }

    // If current < latest => optional update
    if (compareVersions(currentVersion, rule.latestVersion) < 0) {
      return UpdateDecision.optional(
        currentVersion: currentVersion,
        minVersion: rule.minVersion,
        latestVersion: rule.latestVersion,
        storeUrl: rule.storeUrl,
        message: rule.message,
      );
    }

    return UpdateDecision.none(
      currentVersion: currentVersion,
      minVersion: rule.minVersion,
      latestVersion: rule.latestVersion,
    );
  }

  Future<UpdateDecision> checkForPlatform({
    required String appId,
    required AppPlatform platform,
    AppEnvironment? environment,
    required String currentVersion,
  }) {
    return check(
      appId: appId,
      platform: platform,
      environment: environment,
      currentVersion: currentVersion,
    );
  }
}

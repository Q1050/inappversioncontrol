import 'platform/current_app_platform.dart';

/// The action an app should take after checking its version policy.
enum UpdateType { none, optional, force, maintenance }

/// A backend service supported by a version-rule provider.
enum BackendService { firebase, supabase, custom }

/// The deployment environment used to select a version rule.
enum AppEnvironment {
  production('production'),
  staging('staging'),
  testing('testing'),
  development('development');

  /// The value used when sending this environment to a backend.
  final String value;

  /// Creates an environment with its backend [value].
  const AppEnvironment(this.value);

  /// Finds the environment represented by [value].
  ///
  /// Throws an [ArgumentError] when the value is not supported.
  static AppEnvironment fromValue(String value) {
    return AppEnvironment.values.firstWhere(
      (environment) => environment.value == value,
      orElse: () => throw ArgumentError.value(
        value,
        'value',
        'Unsupported app environment value.',
      ),
    );
  }
}

/// A platform that can have its own version policy and store URL.
enum AppPlatform {
  android('android'),
  ios('ios'),
  web('web'),
  macos('macos'),
  windows('windows'),
  linux('linux');

  /// The value used when sending this platform to a backend.
  final String value;

  /// Creates a platform with its backend [value].
  const AppPlatform(this.value);

  /// The platform on which the Flutter app is currently running.
  static AppPlatform get current => currentAppPlatform();

  /// Finds the platform represented by [value].
  ///
  /// Throws an [ArgumentError] when the value is not supported.
  static AppPlatform fromValue(String value) {
    return AppPlatform.values.firstWhere(
      (platform) => platform.value == value,
      orElse: () => throw ArgumentError.value(
        value,
        'value',
        'Unsupported app platform value.',
      ),
    );
  }
}

/// A backend policy describing supported app versions.
class VersionRule {
  /// The oldest version allowed to continue using the app.
  final String minVersion;

  /// The newest version currently available to users.
  final String latestVersion;

  /// The store page where users can update the app.
  final String? storeUrl;

  /// An optional message to show with the decision.
  final String? message;

  /// Whether the app should be unavailable for maintenance.
  final bool maintenance;

  /// Platforms allowed by this rule, or `null` to allow every platform.
  final Set<AppPlatform>? supportedPlatforms;

  /// Creates a version rule returned by a backend.
  const VersionRule({
    required this.minVersion,
    required this.latestVersion,
    this.storeUrl,
    this.message,
    this.maintenance = false,
    this.supportedPlatforms,
  });

  /// Creates a version rule from the package's standard JSON format.
  factory VersionRule.fromJson(Map<String, dynamic> json) {
    return VersionRule(
      minVersion: json['minVersion'] as String,
      latestVersion: json['latestVersion'] as String,
      storeUrl: json['storeUrl'] as String?,
      message: json['message'] as String?,
      maintenance: json['maintenance'] as bool? ?? false,
      supportedPlatforms: _supportedPlatformsFromJson(
        json['supportedPlatforms'],
      ),
    );
  }

  /// Converts this rule to the package's standard JSON format.
  Map<String, dynamic> toJson() {
    return {
      'minVersion': minVersion,
      'latestVersion': latestVersion,
      'storeUrl': storeUrl,
      'message': message,
      'maintenance': maintenance,
      'supportedPlatforms': supportedPlatforms
          ?.map((platform) => platform.value)
          .toList(),
    };
  }

  /// Returns whether this rule allows [platform].
  bool supportsPlatform(AppPlatform platform) {
    return supportedPlatforms == null || supportedPlatforms!.contains(platform);
  }

  static Set<AppPlatform>? _supportedPlatformsFromJson(Object? value) {
    if (value == null) {
      return null;
    }

    final platforms = value as List<dynamic>;
    return platforms
        .map((item) => AppPlatform.fromValue(item as String))
        .toSet();
  }
}

/// The result of comparing an installed app version with a [VersionRule].
class UpdateDecision {
  /// The action the app should take.
  final UpdateType type;

  /// The version currently installed on the device.
  final String currentVersion;

  /// The oldest version allowed by the rule.
  final String minVersion;

  /// The newest version available according to the rule.
  final String latestVersion;

  /// The store page where the user can update the app.
  final String? storeUrl;

  /// An optional message suitable for the app's update or maintenance UI.
  final String? message;

  const UpdateDecision._({
    required this.type,
    required this.currentVersion,
    required this.minVersion,
    required this.latestVersion,
    this.storeUrl,
    this.message,
  });

  /// Creates a decision that allows the app to continue normally.
  factory UpdateDecision.none({
    required String currentVersion,
    required String minVersion,
    required String latestVersion,
  }) => UpdateDecision._(
    type: UpdateType.none,
    currentVersion: currentVersion,
    minVersion: minVersion,
    latestVersion: latestVersion,
  );

  /// Creates a decision that offers an update without requiring it.
  factory UpdateDecision.optional({
    required String currentVersion,
    required String minVersion,
    required String latestVersion,
    String? storeUrl,
    String? message,
  }) => UpdateDecision._(
    type: UpdateType.optional,
    currentVersion: currentVersion,
    minVersion: minVersion,
    latestVersion: latestVersion,
    storeUrl: storeUrl,
    message: message,
  );

  /// Creates a decision that requires an update before continuing.
  factory UpdateDecision.force({
    required String currentVersion,
    required String minVersion,
    required String latestVersion,
    String? storeUrl,
    String? message,
  }) => UpdateDecision._(
    type: UpdateType.force,
    currentVersion: currentVersion,
    minVersion: minVersion,
    latestVersion: latestVersion,
    storeUrl: storeUrl,
    message: message,
  );

  /// Creates a decision that marks the app as unavailable for maintenance.
  factory UpdateDecision.maintenance({
    required String currentVersion,
    required String minVersion,
    required String latestVersion,
    String? message,
  }) => UpdateDecision._(
    type: UpdateType.maintenance,
    currentVersion: currentVersion,
    minVersion: minVersion,
    latestVersion: latestVersion,
    message: message,
  );

  /// Whether the app should show update or maintenance UI.
  bool get requiresAction => type != UpdateType.none;
}

/// Thrown when a version rule does not allow the requested platform.
class UnsupportedAppPlatformException implements Exception {
  /// The platform that was rejected.
  final AppPlatform platform;

  /// The platforms allowed by the rule.
  final Set<AppPlatform> supportedPlatforms;

  /// Creates an unsupported-platform exception.
  const UnsupportedAppPlatformException({
    required this.platform,
    required this.supportedPlatforms,
  });

  @override
  String toString() {
    final values = supportedPlatforms.map((item) => item.value).join(', ');
    return 'UnsupportedAppPlatformException: ${platform.value} is not allowed. '
        'Supported platforms: $values';
  }
}

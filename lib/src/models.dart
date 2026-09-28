import 'platform/current_app_platform.dart';

enum UpdateType { none, optional, force, maintenance }

enum BackendService { firebase, supabase, custom }

enum AppEnvironment {
  production('production'),
  staging('staging'),
  testing('testing'),
  development('development');

  final String value;

  const AppEnvironment(this.value);

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

enum AppPlatform {
  android('android'),
  ios('ios'),
  web('web'),
  macos('macos'),
  windows('windows'),
  linux('linux');

  final String value;

  const AppPlatform(this.value);

  static AppPlatform get current => currentAppPlatform();

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

class VersionRule {
  final String minVersion;
  final String latestVersion;
  final String? storeUrl;
  final String? message;
  final bool maintenance;
  final Set<AppPlatform>? supportedPlatforms;

  const VersionRule({
    required this.minVersion,
    required this.latestVersion,
    this.storeUrl,
    this.message,
    this.maintenance = false,
    this.supportedPlatforms,
  });

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

class UpdateDecision {
  final UpdateType type;
  final String currentVersion;
  final String minVersion;
  final String latestVersion;
  final String? storeUrl;
  final String? message;

  const UpdateDecision._({
    required this.type,
    required this.currentVersion,
    required this.minVersion,
    required this.latestVersion,
    this.storeUrl,
    this.message,
  });

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

  bool get requiresAction => type != UpdateType.none;
}

class UnsupportedAppPlatformException implements Exception {
  final AppPlatform platform;
  final Set<AppPlatform> supportedPlatforms;

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

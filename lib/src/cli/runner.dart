import 'dart:convert';
import 'dart:io';

import '../endpoint_provider.dart';
import '../models.dart';

Future<int> runIavc(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  IavcProcessRunner? processRunner,
  String? workingDirectory,
}) async {
  final output = out ?? stdout;
  final errors = err ?? stderr;
  final context = _IavcContext(
    processRunner: processRunner ?? const _DefaultIavcProcessRunner(),
    workingDirectory: workingDirectory ?? Directory.current.path,
  );

  if (args.isEmpty || _isHelp(args.first)) {
    _writeHelp(output);
    return 0;
  }

  try {
    switch (args.first) {
      case 'rule:validate':
        return await _handleRuleValidate(args.skip(1).toList(), output, errors);
      case 'endpoint:test':
        return await _handleEndpointTest(args.skip(1).toList(), output, errors);
      case 'app:firebase':
        return await _handleFirebaseConfigure(
          args.skip(1).toList(),
          output,
          errors,
          context,
        );
      case 'app:custom':
        return _handleCustomConfigure(args.skip(1).toList(), output, errors);
      default:
        errors.writeln('Unknown command: ${args.first}');
        _writeHelp(errors);
        return 64;
    }
  } on FormatException catch (error) {
    errors.writeln(error.message);
    return 64;
  } on FileSystemException catch (error) {
    errors.writeln(error.message);
    return 66;
  } on EndpointVersionRuleException catch (error) {
    errors.writeln(error);
    return 1;
  } on Object catch (error) {
    errors.writeln(error);
    return 1;
  }
}

Future<int> _handleRuleValidate(
  List<String> args,
  StringSink out,
  StringSink err,
) async {
  if (args.isEmpty) {
    throw const FormatException(
      'Usage: iavc rule:validate <path-to-rule.json>',
    );
  }

  final file = File(args.first);
  final contents = await file.readAsString();
  final decoded = jsonDecode(contents);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Rule file must contain a JSON object.');
  }

  final rule = VersionRule.fromJson(decoded);
  out.writeln('Rule is valid.');
  out.writeln(const JsonEncoder.withIndent('  ').convert(rule.toJson()));
  return 0;
}

Future<int> _handleEndpointTest(
  List<String> args,
  StringSink out,
  StringSink err,
) async {
  if (args.isEmpty) {
    throw const FormatException(
      'Usage: iavc endpoint:test <url> [--method get|post|put|patch] '
      '[--app-id com.example.app] [--platform android] [--header key=value]',
    );
  }

  final url = args.first;
  final options = _parseOptions(args.skip(1).toList());
  final provider = EndpointVersionRuleProvider(
    endpoint: Uri.parse(url),
    method: _parseMethod(options.singleValue('method') ?? 'get'),
    headers: options.multiValue('header').fold(<String, String>{}, (acc, item) {
      final parts = item.split('=');
      if (parts.length != 2) {
        throw FormatException('Header must be in key=value format: $item');
      }
      acc[parts.first] = parts.last;
      return acc;
    }),
  );

  try {
    final platform = AppPlatform.fromValue(
      options.singleValue('platform') ?? AppPlatform.current.value,
    );
    final rule = await provider.fetchRule(
      appId: options.singleValue('app-id') ?? 'com.example.app',
      platform: platform,
    );
    out.writeln('Endpoint rule fetch succeeded.');
    out.writeln('Backend: ${provider.backendService.name}');
    out.writeln(const JsonEncoder.withIndent('  ').convert(rule.toJson()));
    return 0;
  } finally {
    provider.close();
  }
}

Future<int> _handleFirebaseConfigure(
  List<String> args,
  StringSink out,
  StringSink err,
  _IavcContext context,
) async {
  if (args.isEmpty || args.first != 'configure') {
    throw const FormatException(
      'Usage: iavc app:firebase configure [--mode remote-config] '
      '[--project <projectId>] [--android-package <package>] '
      '[--ios-bundle-id <bundleId>] [--web-app-name <name>] '
      '[--android-app-name <name>] [--ios-app-name <name>] '
      '[--write-alias <alias>] [--out-dir <directory>] '
      '[--deploy-remoteconfig true|false]',
    );
  }

  final options = _parseOptions(args.skip(1).toList());
  final mode = options.singleValue('mode') ?? 'remote-config';
  final deployRemoteConfig =
      (options.singleValue('deploy-remoteconfig') ?? 'false').toLowerCase() ==
      'true';
  if (mode != 'remote-config') {
    throw FormatException('Unsupported Firebase mode: $mode');
  }

  final firebase = _FirebaseCli(
    processRunner: context.processRunner,
    workingDirectory: context.workingDirectory,
  );

  await firebase.checkInstalled();

  final projects = await firebase.listProjects();
  if (projects.isEmpty) {
    err.writeln(
      'No Firebase projects were found for the current login. '
      'Run `firebase login` or create a project first.',
    );
    return 1;
  }

  final requestedProject = options.singleValue('project');
  final resolvedProject =
      requestedProject ??
      _readDefaultFirebaseProject(context.workingDirectory) ??
      _readFlutterFireProject(context.workingDirectory) ??
      (projects.length == 1 ? projects.single.id : null);

  if (resolvedProject == null) {
    err.writeln(
      'Multiple Firebase projects are available. Pass `--project <projectId>`.',
    );
    err.writeln('Available projects:');
    for (final project in projects) {
      err.writeln('- ${project.id}${project.displayNameSuffix}');
    }
    return 64;
  }

  final projectExists = projects.any(
    (project) => project.id == resolvedProject,
  );
  if (!projectExists) {
    err.writeln('Firebase project not found: $resolvedProject');
    return 64;
  }

  var apps = await firebase.listApps(resolvedProject);

  final androidPackage =
      options.singleValue('android-package') ??
      _readAndroidPackage(context.workingDirectory);
  final androidApps = apps.where((app) => app.platform == 'ANDROID').toList();
  final hasMatchingAndroidApp =
      androidPackage != null &&
      androidApps.any((app) => app.namespace == androidPackage);
  final androidNamespacesUnavailable =
      androidApps.isNotEmpty &&
      androidApps.every((app) => app.namespace == null);
  if (androidPackage != null &&
      !hasMatchingAndroidApp &&
      !androidNamespacesUnavailable) {
    await firebase.createAndroidApp(
      projectId: resolvedProject,
      packageName: androidPackage,
      displayName: options.singleValue('android-app-name') ?? 'Android App',
    );
  }

  final iosBundleId = options.singleValue('ios-bundle-id');
  if (iosBundleId != null && !apps.any((app) => app.platform == 'IOS')) {
    await firebase.createIosApp(
      projectId: resolvedProject,
      bundleId: iosBundleId,
      displayName: options.singleValue('ios-app-name') ?? 'iOS App',
    );
  }

  final webAppName = options.singleValue('web-app-name');
  if (webAppName != null && !apps.any((app) => app.platform == 'WEB')) {
    await firebase.createWebApp(
      projectId: resolvedProject,
      displayName: webAppName,
    );
  }

  apps = await firebase.listApps(resolvedProject);

  final outDirPath = options.singleValue('out-dir') ?? context.workingDirectory;
  final outDir = Directory(outDirPath);
  await outDir.create(recursive: true);

  final keys = _buildRemoteConfigKeys(apps);
  final templateFile = File('${outDir.path}/remoteconfig.template.json');
  await templateFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(
      _buildRemoteConfigTemplate(
        keys.values.expand((platformKeys) => platformKeys.values).toList(),
      ),
    ),
  );

  final firebaseJsonFile = File('${outDir.path}/firebase.json');
  await firebaseJsonFile.writeAsString(
    const JsonEncoder.withIndent(
      '  ',
    ).convert(await _mergeFirebaseJson(firebaseJsonFile)),
  );

  final alias = options.singleValue('write-alias');
  if (alias != null && alias.isNotEmpty) {
    final firebasercFile = File('${outDir.path}/.firebaserc');
    await firebasercFile.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(await _mergeFirebaserc(firebasercFile, alias, resolvedProject)),
    );
  }

  if (deployRemoteConfig) {
    await firebase.deployRemoteConfig(
      projectId: resolvedProject,
      workingDirectoryOverride: outDir.path,
    );
  }

  out.writeln('Firebase Remote Config setup completed.');
  out.writeln('');
  out.writeln('Project: $resolvedProject');
  out.writeln('Detected apps:');
  if (apps.isEmpty) {
    out.writeln('- none');
  } else {
    for (final app in apps) {
      out.writeln('- ${app.platform}: ${app.displayName}');
    }
  }
  out.writeln('');
  out.writeln('Remote Config keys written:');
  for (final environmentEntry in keys.entries) {
    for (final platformEntry in environmentEntry.value.entries) {
      out.writeln(
        '- ${environmentEntry.key.value}/${platformEntry.key.value}: '
        '${platformEntry.value}',
      );
    }
  }
  out.writeln('');
  out.writeln('Files written:');
  out.writeln('- ${templateFile.path}');
  out.writeln('- ${firebaseJsonFile.path}');
  if (alias != null && alias.isNotEmpty) {
    out.writeln('- ${outDir.path}/.firebaserc');
  }
  if (deployRemoteConfig) {
    out.writeln('- Remote Config deployed to Firebase');
  }
  out.writeln('');
  out.writeln('Sample Remote Config value:');
  out.writeln(_sampleRuleJson());
  out.writeln('');
  out.writeln('Dart usage:');
  out.writeln('''
final versionControl = InAppVersionControl(
  provider: FirebaseVersionRuleProvider.remoteConfig(
    environmentKeys: {
${_renderFirebaseKeys(keys)}
    },
  ),
);
''');
  out.writeln('');
  out.writeln('Next steps:');
  if (deployRemoteConfig) {
    out.writeln('- Verify the published parameters in Firebase Remote Config.');
  } else {
    out.writeln(
      '- Populate ${templateFile.path} or publish it with your Firebase workflow.',
    );
    out.writeln(
      '- Re-run this command with `--deploy-remoteconfig true` to publish automatically.',
    );
  }
  out.writeln('- Run `firebase use $resolvedProject` if needed.');
  return 0;
}

int _handleCustomConfigure(List<String> args, StringSink out, StringSink err) {
  if (args.isEmpty || args.first != 'configure') {
    throw const FormatException(
      'Usage: iavc app:custom configure [--method get|post|put|patch]',
    );
  }

  final options = _parseOptions(args.skip(1).toList());
  final method = options.singleValue('method') ?? 'post';

  out.writeln('Custom backend setup');
  out.writeln('');
  out.writeln('Request payload:');
  out.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'appId': 'com.example.app',
      'platform': 'android',
      'environment': 'production',
    }),
  );
  out.writeln('');
  out.writeln('Response payload:');
  out.writeln(_sampleRuleJson());
  out.writeln('');
  out.writeln('Dart usage:');
  out.writeln('''
final versionControl = InAppVersionControl(
  provider: EndpointVersionRuleProvider(
    endpoint: Uri.parse('https://api.example.com/version-rule'),
    method: EndpointRequestMethod.${method.toLowerCase()},
  ),
);
''');
  return 0;
}

EndpointRequestMethod _parseMethod(String value) {
  return switch (value.toLowerCase()) {
    'get' => EndpointRequestMethod.get,
    'post' => EndpointRequestMethod.post,
    'put' => EndpointRequestMethod.put,
    'patch' => EndpointRequestMethod.patch,
    _ => throw FormatException('Unsupported HTTP method: $value'),
  };
}

_CliOptions _parseOptions(List<String> args) {
  final single = <String, String>{};
  final multi = <String, List<String>>{};

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) {
      throw FormatException('Unexpected argument: $arg');
    }
    final key = arg.substring(2);
    if (i + 1 >= args.length) {
      throw FormatException('Missing value for --$key');
    }
    final value = args[++i];
    multi.putIfAbsent(key, () => <String>[]).add(value);
    single[key] = value;
  }

  return _CliOptions(single: single, multi: multi);
}

String _sampleRuleJson({bool inline = false}) {
  final payload = {
    'minVersion': '1.0.0',
    'latestVersion': '1.2.0',
    'storeUrl': 'https://example.com/store',
    'message': 'Update available',
    'maintenance': false,
    'supportedPlatforms': ['android', 'ios'],
  };
  return inline
      ? jsonEncode(payload)
      : const JsonEncoder.withIndent('  ').convert(payload);
}

void _writeHelp(StringSink out) {
  out.writeln('iavc commands:');
  out.writeln('- iavc rule:validate <path-to-rule.json>');
  out.writeln(
    '- iavc endpoint:test <url> [--method get|post|put|patch] '
    '[--app-id com.example.app] [--platform android] [--header key=value]',
  );
  out.writeln(
    '- iavc app:firebase configure [--mode remote-config] '
    '[--project <projectId>] [--android-package <package>] '
    '[--ios-bundle-id <bundleId>] [--web-app-name <name>] '
    '[--deploy-remoteconfig true|false]',
  );
  out.writeln('- iavc app:custom configure [--method get|post|put|patch]');
}

bool _isHelp(String arg) => arg == 'help' || arg == '--help' || arg == '-h';

class _CliOptions {
  final Map<String, String> single;
  final Map<String, List<String>> multi;

  const _CliOptions({required this.single, required this.multi});

  String? singleValue(String key) => single[key];

  List<String> multiValue(String key) => multi[key] ?? const <String>[];
}

class _IavcContext {
  final IavcProcessRunner processRunner;
  final String workingDirectory;

  const _IavcContext({
    required this.processRunner,
    required this.workingDirectory,
  });
}

abstract class IavcProcessRunner {
  Future<IavcCommandResult> run(
    String executable,
    List<String> args, {
    required String workingDirectory,
    Map<String, String>? environment,
  });
}

class IavcCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const IavcCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

class _DefaultIavcProcessRunner implements IavcProcessRunner {
  const _DefaultIavcProcessRunner();

  @override
  Future<IavcCommandResult> run(
    String executable,
    List<String> args, {
    required String workingDirectory,
    Map<String, String>? environment,
  }) async {
    final result = await Process.run(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    return IavcCommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }
}

class _FirebaseCli {
  final IavcProcessRunner processRunner;
  final String workingDirectory;

  const _FirebaseCli({
    required this.processRunner,
    required this.workingDirectory,
  });

  Map<String, String> get _environment => {
    'FIREBASE_SKIP_UPDATE_CHECK': '1',
    'CI': '1',
  };

  Future<void> checkInstalled() async {
    final result = await processRunner.run(
      'firebase',
      ['--version'],
      workingDirectory: workingDirectory,
      environment: _environment,
    );
    if (result.exitCode != 0) {
      throw FormatException(
        'Firebase CLI is not available. Install firebase-tools first.',
      );
    }
  }

  Future<List<_FirebaseProject>> listProjects() async {
    final result = await processRunner.run(
      'firebase',
      ['--json', 'projects:list'],
      workingDirectory: workingDirectory,
      environment: _environment,
    );
    if (result.exitCode != 0) {
      if (_looksLikeAuthFailure(result.stdout) ||
          _looksLikeAuthFailure(result.stderr)) {
        throw FormatException(
          'Firebase CLI is not authenticated. Run `firebase login` first.',
        );
      }
      throw FormatException(_bestError(result));
    }
    final decoded = jsonDecode(result.stdout) as Map<String, dynamic>;
    final items = _extractObjectList(decoded, ['projectId']);
    return items
        .map(
          (item) => _FirebaseProject(
            id: item['projectId'] as String,
            displayName: item['displayName'] as String?,
          ),
        )
        .toList();
  }

  Future<List<_FirebaseApp>> listApps(String projectId) async {
    final result = await processRunner.run(
      'firebase',
      ['--json', 'apps:list', '--project', projectId],
      workingDirectory: workingDirectory,
      environment: _environment,
    );
    if (result.exitCode != 0) {
      throw FormatException(_bestError(result));
    }
    final decoded = jsonDecode(result.stdout) as Map<String, dynamic>;
    final items = _extractObjectList(decoded, ['platform']);
    return items
        .map(
          (item) => _FirebaseApp(
            platform: (item['platform'] as String).toUpperCase(),
            appId: item['appId'] as String?,
            namespace: item['namespace'] as String?,
            displayName:
                item['displayName'] as String? ??
                item['name'] as String? ??
                'Unnamed App',
          ),
        )
        .toList();
  }

  Future<void> createAndroidApp({
    required String projectId,
    required String packageName,
    required String displayName,
  }) async {
    final result = await processRunner.run(
      'firebase',
      [
        'apps:create',
        'ANDROID',
        displayName,
        '--package-name',
        packageName,
        '--project',
        projectId,
      ],
      workingDirectory: workingDirectory,
      environment: _environment,
    );
    if (result.exitCode != 0) {
      throw FormatException(_bestError(result));
    }
  }

  Future<void> createIosApp({
    required String projectId,
    required String bundleId,
    required String displayName,
  }) async {
    final result = await processRunner.run(
      'firebase',
      [
        'apps:create',
        'IOS',
        displayName,
        '--bundle-id',
        bundleId,
        '--project',
        projectId,
      ],
      workingDirectory: workingDirectory,
      environment: _environment,
    );
    if (result.exitCode != 0) {
      throw FormatException(_bestError(result));
    }
  }

  Future<void> createWebApp({
    required String projectId,
    required String displayName,
  }) async {
    final result = await processRunner.run(
      'firebase',
      ['apps:create', 'WEB', displayName, '--project', projectId],
      workingDirectory: workingDirectory,
      environment: _environment,
    );
    if (result.exitCode != 0) {
      throw FormatException(_bestError(result));
    }
  }

  Future<void> deployRemoteConfig({
    required String projectId,
    required String workingDirectoryOverride,
  }) async {
    final result = await processRunner.run(
      'firebase',
      ['deploy', '--only', 'remoteconfig', '--project', projectId],
      workingDirectory: workingDirectoryOverride,
      environment: _environment,
    );
    if (result.exitCode != 0) {
      throw FormatException(_bestError(result));
    }
  }
}

class _FirebaseProject {
  final String id;
  final String? displayName;

  const _FirebaseProject({required this.id, required this.displayName});

  String get displayNameSuffix =>
      displayName == null || displayName == id ? '' : ' ($displayName)';
}

class _FirebaseApp {
  final String platform;
  final String? appId;
  final String? namespace;
  final String displayName;

  const _FirebaseApp({
    required this.platform,
    required this.appId,
    required this.namespace,
    required this.displayName,
  });
}

String? _readAndroidPackage(String workingDirectory) {
  final candidates = [
    File('$workingDirectory/android/app/build.gradle.kts'),
    File('$workingDirectory/android/app/build.gradle'),
  ];

  for (final file in candidates) {
    if (!file.existsSync()) {
      continue;
    }
    final match = RegExp(
      r'''applicationId\s*(?:=\s*)?["']([^"']+)["']''',
    ).firstMatch(file.readAsStringSync());
    if (match != null) {
      return match.group(1);
    }
  }
  return null;
}

String? _readDefaultFirebaseProject(String workingDirectory) {
  final file = File('$workingDirectory/.firebaserc');
  if (!file.existsSync()) {
    return null;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final projects = decoded['projects'];
    if (projects is Map<String, dynamic>) {
      final defaultProject = projects['default'];
      if (defaultProject is String && defaultProject.isNotEmpty) {
        return defaultProject;
      }
    }
  } on Object {
    return null;
  }
  return null;
}

String? _readFlutterFireProject(String workingDirectory) {
  final file = File('$workingDirectory/firebase.json');
  if (!file.existsSync()) {
    return null;
  }

  try {
    final projectIds = <String>{};

    void collectProjectIds(Object? value) {
      if (value is Map<String, dynamic>) {
        final projectId = value['projectId'];
        if (projectId is String && projectId.isNotEmpty) {
          projectIds.add(projectId);
        }
        for (final child in value.values) {
          collectProjectIds(child);
        }
      } else if (value is List) {
        for (final child in value) {
          collectProjectIds(child);
        }
      }
    }

    collectProjectIds(jsonDecode(file.readAsStringSync()));
    return projectIds.length == 1 ? projectIds.single : null;
  } on Object {
    return null;
  }
}

Map<AppEnvironment, Map<AppPlatform, String>> _buildRemoteConfigKeys(
  List<_FirebaseApp> apps,
) {
  final platforms = apps
      .map((app) => _platformFromFirebaseApp(app.platform))
      .whereType<AppPlatform>()
      .toSet();

  if (platforms.isEmpty) {
    platforms.addAll({AppPlatform.android, AppPlatform.ios, AppPlatform.web});
  }

  return {
    for (final environment in AppEnvironment.values)
      environment: {
        for (final platform in platforms)
          platform: 'version_rule_${platform.value}_${environment.value}',
      },
  };
}

AppPlatform? _platformFromFirebaseApp(String platform) {
  return switch (platform.toUpperCase()) {
    'ANDROID' => AppPlatform.android,
    'IOS' => AppPlatform.ios,
    'WEB' => AppPlatform.web,
    _ => null,
  };
}

Map<String, dynamic> _buildRemoteConfigTemplate(List<String> keys) {
  final parameters = <String, dynamic>{};
  for (final key in keys) {
    parameters[key] = {
      'defaultValue': {'value': _sampleRuleJson(inline: true)},
      'description': 'In-app version control rule for $key',
    };
  }
  return {'parameters': parameters};
}

String _renderFirebaseKeys(Map<AppEnvironment, Map<AppPlatform, String>> keys) {
  return keys.entries
      .map(
        (environmentEntry) =>
            '      AppEnvironment.${environmentEntry.key.name}: {\n'
            '${environmentEntry.value.entries.map((entry) => "        AppPlatform.${entry.key.name}: '${entry.value}',").join('\n')}\n'
            '      },',
      )
      .join('\n');
}

Future<Map<String, dynamic>> _mergeFirebaseJson(File file) async {
  final contents = file.existsSync()
      ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
      : <String, dynamic>{};
  contents['remoteconfig'] = {'template': 'remoteconfig.template.json'};
  return contents;
}

Future<Map<String, dynamic>> _mergeFirebaserc(
  File file,
  String alias,
  String projectId,
) async {
  final contents = file.existsSync()
      ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
      : <String, dynamic>{};
  final projects = Map<String, dynamic>.from(
    contents['projects'] as Map<String, dynamic>? ?? const {},
  );
  projects[alias] = projectId;
  contents['projects'] = projects;
  return contents;
}

bool _looksLikeAuthFailure(String text) {
  return text.contains('Failed to authenticate') ||
      text.contains('firebase login') ||
      text.contains('not authenticated');
}

String _bestError(IavcCommandResult result) {
  final stdout = result.stdout.trim();
  final stderr = result.stderr.trim();
  if (stderr.isNotEmpty) {
    return stderr;
  }
  if (stdout.isNotEmpty) {
    return stdout;
  }
  return 'Firebase CLI command failed with exit code ${result.exitCode}.';
}

List<Map<String, dynamic>> _extractObjectList(
  Object? node,
  List<String> requiredKeys,
) {
  final results = <Map<String, dynamic>>[];

  void visit(Object? value) {
    if (value is Map<String, dynamic>) {
      final hasAllKeys = requiredKeys.every(value.containsKey);
      if (hasAllKeys) {
        results.add(value);
      }
      for (final child in value.values) {
        visit(child);
      }
    } else if (value is List) {
      for (final child in value) {
        visit(child);
      }
    }
  }

  visit(node);
  return results;
}

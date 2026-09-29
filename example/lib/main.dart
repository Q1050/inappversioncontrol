import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:in_app_version_control/in_app_version_control.dart';

void main() {
  runApp(const VersionControlExampleApp());
}

class VersionControlExampleApp extends StatelessWidget {
  const VersionControlExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'In App Version Control Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6E4F)),
      ),
      home: const VersionControlExamplePage(),
    );
  }
}

class VersionControlExamplePage extends StatefulWidget {
  const VersionControlExamplePage({super.key});

  @override
  State<VersionControlExamplePage> createState() =>
      _VersionControlExamplePageState();
}

class _VersionControlExamplePageState extends State<VersionControlExamplePage> {
  _Scenario _scenario = _Scenario.upToDate;
  AppPlatform _platform = AppPlatform.android;
  AppEnvironment _environment = AppEnvironment.production;
  _ProviderMode _providerMode = _ProviderMode.memory;

  InAppVersionControl _buildVersionControl() {
    return InAppVersionControl(
      provider: switch (_providerMode) {
        _ProviderMode.memory => DemoProvider(_scenario.rule),
        _ProviderMode.firebaseMock =>
          FirebaseVersionRuleProvider.remoteConfigClient(
            remoteConfigClient: _ExampleFirebaseRemoteConfigClient(
              values: {
                AppPlatform.android: _scenario.rule,
                AppPlatform.ios: _scenario.rule,
                AppPlatform.web: _scenario.rule,
                AppPlatform.macos: _scenario.rule,
                AppPlatform.windows: _scenario.rule,
                AppPlatform.linux: _scenario.rule,
              },
            ),
            keys: const {
              AppPlatform.android: 'version_rule_android',
              AppPlatform.ios: 'version_rule_ios',
              AppPlatform.web: 'version_rule_web',
              AppPlatform.macos: 'version_rule_macos',
              AppPlatform.windows: 'version_rule_windows',
              AppPlatform.linux: 'version_rule_linux',
            },
            shouldFetchAndActivate: false,
          ),
      },
    );
  }

  Future<UpdateDecision> _runCheck() {
    final versionControl = _buildVersionControl();
    return versionControl.check(
      appId: 'com.example.myapp',
      platform: _platform,
      environment: _environment,
      currentVersion: _scenario.currentVersion,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('In App Version Control')),
      body: FutureBuilder<UpdateDecision>(
        future: _runCheck(),
        builder: (context, snapshot) {
          final decision = snapshot.data;
          final versionControl = _buildVersionControl();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Provider',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_ProviderMode>(
                initialValue: _providerMode,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Backend integration',
                ),
                items: _ProviderMode.values.map((mode) {
                  return DropdownMenuItem<_ProviderMode>(
                    value: mode,
                    child: Text(mode.label),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _providerMode = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              _InfoTile(
                title: 'Backend service',
                value: versionControl.backendService.name,
              ),
              if (_providerMode == _ProviderMode.firebaseMock) ...[
                const SizedBox(height: 8),
                const Text(
                  'This uses the real FirebaseVersionRuleProvider API with a '
                  'mocked Remote Config client so you can test the Firebase flow locally.',
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Scenario',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_Scenario>(
                initialValue: _scenario,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Decision scenario',
                ),
                items: _Scenario.values.map((scenario) {
                  return DropdownMenuItem<_Scenario>(
                    value: scenario,
                    child: Text(scenario.label),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _scenario = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AppEnvironment>(
                initialValue: _environment,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'App environment',
                ),
                items: AppEnvironment.values.map((environment) {
                  return DropdownMenuItem<AppEnvironment>(
                    value: environment,
                    child: Text(environment.value),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _environment = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AppPlatform>(
                initialValue: _platform,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'App platform',
                ),
                items: AppPlatform.values.map((platform) {
                  return DropdownMenuItem<AppPlatform>(
                    value: platform,
                    child: Text(platform.value),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _platform = value;
                  });
                },
              ),
              const SizedBox(height: 24),
              _InfoTile(
                title: 'Current version',
                value: _scenario.currentVersion,
              ),
              _InfoTile(
                title: 'Minimum supported version',
                value: _scenario.rule.minVersion,
              ),
              _InfoTile(
                title: 'Latest available version',
                value: _scenario.rule.latestVersion,
              ),
              const SizedBox(height: 24),
              const Text(
                'Decision',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (snapshot.hasError)
                _ErrorCard(error: snapshot.error!)
              else if (!snapshot.hasData)
                const Center(child: CircularProgressIndicator())
              else
                _DecisionCard(decision: decision!),
            ],
          );
        },
      ),
    );
  }
}

class DemoProvider implements VersionRuleProvider {
  final VersionRule rule;

  const DemoProvider(this.rule);

  @override
  BackendService get backendService => BackendService.custom;

  @override
  Future<VersionRule> fetchRule({
    required String appId,
    required AppPlatform platform,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return rule;
  }
}

class _ExampleFirebaseRemoteConfigClient implements FirebaseRemoteConfigClient {
  final Map<AppPlatform, VersionRule> values;

  const _ExampleFirebaseRemoteConfigClient({required this.values});

  @override
  Future<bool> fetchAndActivate() async => true;

  @override
  String getString(String key) {
    final platform = switch (key) {
      'version_rule_android' => AppPlatform.android,
      'version_rule_ios' => AppPlatform.ios,
      'version_rule_web' => AppPlatform.web,
      'version_rule_macos' => AppPlatform.macos,
      'version_rule_windows' => AppPlatform.windows,
      'version_rule_linux' => AppPlatform.linux,
      _ => throw StateError('Unknown Remote Config key: $key'),
    };

    final rule = values[platform];
    if (rule == null) {
      return '';
    }

    return _encodeRule(rule);
  }

  String _encodeRule(VersionRule rule) {
    return jsonEncode(rule.toJson());
  }
}

class _ErrorCard extends StatelessWidget {
  final Object error;

  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          error.toString(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  final UpdateDecision decision;

  const _DecisionCard({required this.decision});

  Color get _accentColor {
    switch (decision.type) {
      case UpdateType.none:
        return const Color(0xFF0B6E4F);
      case UpdateType.optional:
        return const Color(0xFFB26A00);
      case UpdateType.force:
        return const Color(0xFFB3261E);
      case UpdateType.maintenance:
        return const Color(0xFF5B3FD4);
    }
  }

  String get _title {
    switch (decision.type) {
      case UpdateType.none:
        return 'Up to date';
      case UpdateType.optional:
        return 'Optional update';
      case UpdateType.force:
        return 'Forced update';
      case UpdateType.maintenance:
        return 'Maintenance mode';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _accentColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_outlined, color: _accentColor),
              const SizedBox(width: 10),
              Text(
                _title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Type: ${decision.type.name}'),
          Text('Current: ${decision.currentVersion}'),
          Text('Minimum: ${decision.minVersion}'),
          Text('Latest: ${decision.latestVersion}'),
          if (decision.message != null) ...[
            const SizedBox(height: 12),
            Text(
              decision.message!,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          if (decision.storeUrl != null) ...[
            const SizedBox(height: 8),
            SelectableText(decision.storeUrl!),
          ],
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String title;
  final String value;

  const _InfoTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E3E7)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value),
        ],
      ),
    );
  }
}

enum _Scenario {
  upToDate(
    label: 'Up to date',
    currentVersion: '1.2.0',
    rule: VersionRule(
      minVersion: '1.0.0',
      latestVersion: '1.2.0',
      message: 'You are running the latest version.',
    ),
  ),
  optionalUpdate(
    label: 'Optional update',
    currentVersion: '1.1.0',
    rule: VersionRule(
      minVersion: '1.0.0',
      latestVersion: '1.2.0',
      storeUrl: 'https://example.com/store',
      message: 'A newer version is available.',
    ),
  ),
  forcedUpdate(
    label: 'Force update',
    currentVersion: '0.9.0',
    rule: VersionRule(
      minVersion: '1.0.0',
      latestVersion: '1.2.0',
      storeUrl: 'https://example.com/store',
      message: 'You must update before continuing.',
    ),
  ),
  maintenance(
    label: 'Maintenance mode',
    currentVersion: '9.9.9',
    rule: VersionRule(
      minVersion: '1.0.0',
      latestVersion: '1.2.0',
      maintenance: true,
      message: 'The service is temporarily unavailable for maintenance.',
    ),
  );

  final String label;
  final String currentVersion;
  final VersionRule rule;

  const _Scenario({
    required this.label,
    required this.currentVersion,
    required this.rule,
  });
}

enum _ProviderMode {
  memory(label: 'In-memory provider'),
  firebaseMock(label: 'Firebase Remote Config (mock)');

  final String label;

  const _ProviderMode({required this.label});
}

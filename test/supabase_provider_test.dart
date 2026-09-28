import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_version_control/in_app_version_control.dart';

void main() {
  test('supabase provider identifies itself as a supabase backend', () {
    final provider = SupabaseVersionRuleProvider.client(
      client: _FakeSupabaseTableClient(
        rows: const [
          {
            'app_id': 'com.example.app',
            'platform': 'android',
            'environment': 'production',
            'minVersion': '1.0.0',
            'latestVersion': '1.2.0',
          },
        ],
      ),
      table: 'app_version_rules',
    );

    expect(provider.backendService, BackendService.supabase);
  });

  test('supabase provider fetches a rule for app id and platform', () async {
    final fakeClient = _FakeSupabaseTableClient(
      rows: const [
        {
          'app_id': 'com.example.app',
          'platform': 'android',
          'environment': 'production',
          'minVersion': '1.0.0',
          'latestVersion': '1.2.0',
          'maintenance': false,
        },
      ],
    );
    final provider = SupabaseVersionRuleProvider.client(
      client: fakeClient,
      table: 'app_version_rules',
    );

    final rule = await provider.fetchRule(
      appId: 'com.example.app',
      platform: AppPlatform.android,
    );

    expect(rule.minVersion, '1.0.0');
    expect(rule.latestVersion, '1.2.0');
    expect(fakeClient.lastFilters, {
      'app_id': 'com.example.app',
      'platform': 'android',
      'environment': 'production',
    });
  });

  test('supabase provider supports custom column names', () async {
    final fakeClient = _FakeSupabaseTableClient(
      rows: const [
        {
          'application_id': 'com.example.app',
          'runtime': 'ios',
          'stage': 'production',
          'minVersion': '1.5.0',
          'latestVersion': '2.0.0',
        },
      ],
    );
    final provider = SupabaseVersionRuleProvider.client(
      client: fakeClient,
      table: 'mobile_rules',
      appIdColumn: 'application_id',
      platformColumn: 'runtime',
      environmentColumn: 'stage',
    );

    final rule = await provider.fetchRule(
      appId: 'com.example.app',
      platform: AppPlatform.ios,
    );

    expect(rule.minVersion, '1.5.0');
    expect(fakeClient.lastFilters, {
      'application_id': 'com.example.app',
      'runtime': 'ios',
      'stage': 'production',
    });
  });

  test('supabase provider supports custom row mapping', () async {
    final provider = SupabaseVersionRuleProvider.client(
      client: _FakeSupabaseTableClient(
        rows: const [
          {
            'app_id': 'com.example.app',
            'platform': 'android',
            'environment': 'production',
            'minimum_supported': '1.0.0',
            'latest_available': '1.3.0',
            'notice': 'Upgrade recommended',
          },
        ],
      ),
      table: 'app_version_rules',
      ruleBuilder: (json) => VersionRule(
        minVersion: json['minimum_supported'] as String,
        latestVersion: json['latest_available'] as String,
        message: json['notice'] as String?,
      ),
    );

    final rule = await provider.fetchRule(
      appId: 'com.example.app',
      platform: AppPlatform.android,
    );

    expect(rule.latestVersion, '1.3.0');
    expect(rule.message, 'Upgrade recommended');
  });

  test('supabase provider filters by the selected environment', () async {
    final fakeClient = _FakeSupabaseTableClient(
      rows: const [
        {
          'app_id': 'com.example.app',
          'platform': 'android',
          'environment': 'testing',
          'minVersion': '2.0.0',
          'latestVersion': '2.1.0',
        },
      ],
    );
    final provider = SupabaseVersionRuleProvider.client(
      client: fakeClient,
      table: 'app_version_rules',
    );

    final rule = await provider.fetchRuleForEnvironment(
      appId: 'com.example.app',
      platform: AppPlatform.android,
      environment: AppEnvironment.testing,
    );

    expect(rule.minVersion, '2.0.0');
    expect(fakeClient.lastFilters?['environment'], 'testing');
  });
}

class _FakeSupabaseTableClient implements SupabaseTableClient {
  final List<Map<String, dynamic>> rows;
  Map<String, Object?>? lastFilters;

  _FakeSupabaseTableClient({required this.rows});

  @override
  Future<Map<String, dynamic>> fetchSingleRow({
    required String table,
    required String? schema,
    required String selectColumns,
    required Map<String, Object?> filters,
  }) async {
    lastFilters = Map<String, Object?>.from(filters);

    return rows.firstWhere(
      (row) => filters.entries.every((entry) => row[entry.key] == entry.value),
    );
  }
}

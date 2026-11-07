import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_version_control/in_app_version_control.dart';

void main() {
  test('supabase provider identifies itself as a supabase backend', () {
    final provider = SupabaseVersionRuleProvider.client(
      client: _FakeSupabaseTableClient(rows: const []),
      table: 'app_version_rules',
    );

    expect(provider.backendService, BackendService.supabase);
  });

  test('supabase provider fetches by app, platform, and environment', () async {
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
    expect(fakeClient.lastFilters, {
      'app_id': 'com.example.app',
      'platform': 'android',
      'environment': 'testing',
    });
  });

  test('supabase provider supports custom row mapping', () async {
    final provider = SupabaseVersionRuleProvider.client(
      client: _FakeSupabaseTableClient(
        rows: const [
          {
            'app_id': 'com.example.app',
            'platform': 'ios',
            'environment': 'production',
            'minimum_supported': '1.0.0',
            'latest_available': '1.3.0',
          },
        ],
      ),
      table: 'app_version_rules',
      ruleBuilder: (json) => VersionRule(
        minVersion: json['minimum_supported'] as String,
        latestVersion: json['latest_available'] as String,
      ),
    );

    final rule = await provider.fetchRule(
      appId: 'com.example.app',
      platform: AppPlatform.ios,
    );

    expect(rule.latestVersion, '1.3.0');
  });

  test('supabase provider forwards custom schema and column names', () async {
    final fakeClient = _FakeSupabaseTableClient(
      rows: const [
        {
          'application': 'com.example.app',
          'runtime': 'web',
          'stage': 'staging',
          'minVersion': '1.0.0',
          'latestVersion': '1.1.0',
        },
      ],
    );
    final provider = SupabaseVersionRuleProvider.client(
      client: fakeClient,
      table: 'release_rules',
      schema: 'mobile',
      appIdColumn: 'application',
      platformColumn: 'runtime',
      environmentColumn: 'stage',
      selectColumns: 'minVersion,latestVersion',
    );

    await provider.fetchRuleForEnvironment(
      appId: 'com.example.app',
      platform: AppPlatform.web,
      environment: AppEnvironment.staging,
    );

    expect(fakeClient.lastTable, 'release_rules');
    expect(fakeClient.lastSchema, 'mobile');
    expect(fakeClient.lastSelectColumns, 'minVersion,latestVersion');
  });

  test('supabase provider wraps query failures', () async {
    final provider = SupabaseVersionRuleProvider.client(
      client: _ThrowingSupabaseTableClient(),
      table: 'app_version_rules',
    );

    expect(
      () => provider.fetchRule(
        appId: 'com.example.app',
        platform: AppPlatform.android,
      ),
      throwsA(
        isA<SupabaseVersionRuleException>().having(
          (error) => error.message,
          'message',
          contains('Failed to fetch'),
        ),
      ),
    );
  });
}

class _FakeSupabaseTableClient implements SupabaseTableClient {
  final List<Map<String, dynamic>> rows;
  Map<String, Object>? lastFilters;
  String? lastTable;
  String? lastSchema;
  String? lastSelectColumns;

  _FakeSupabaseTableClient({required this.rows});

  @override
  Future<Map<String, dynamic>> fetchSingleRow({
    required String table,
    required String? schema,
    required String selectColumns,
    required Map<String, Object> filters,
  }) async {
    lastTable = table;
    lastSchema = schema;
    lastSelectColumns = selectColumns;
    lastFilters = Map<String, Object>.from(filters);
    return rows.firstWhere(
      (row) => filters.entries.every((entry) => row[entry.key] == entry.value),
    );
  }
}

class _ThrowingSupabaseTableClient implements SupabaseTableClient {
  @override
  Future<Map<String, dynamic>> fetchSingleRow({
    required String table,
    required String? schema,
    required String selectColumns,
    required Map<String, Object> filters,
  }) async {
    throw StateError('offline');
  }
}

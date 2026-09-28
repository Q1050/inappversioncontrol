import 'models.dart';
import 'provider.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

typedef SupabaseRuleBuilder = VersionRule Function(Map<String, dynamic> json);

class SupabaseVersionRuleProvider implements EnvironmentVersionRuleProvider {
  final SupabaseTableClient _client;
  final String table;
  final String? schema;
  final String appIdColumn;
  final String platformColumn;
  final String environmentColumn;
  final String selectColumns;
  final SupabaseRuleBuilder ruleBuilder;

  SupabaseVersionRuleProvider({
    SupabaseClient? client,
    required this.table,
    this.schema,
    this.appIdColumn = 'app_id',
    this.platformColumn = 'platform',
    this.environmentColumn = 'environment',
    this.selectColumns = '*',
    SupabaseRuleBuilder? ruleBuilder,
  }) : _client = _SupabaseTableClient(client ?? Supabase.instance.client),
       ruleBuilder = ruleBuilder ?? VersionRule.fromJson;

  SupabaseVersionRuleProvider.client({
    required SupabaseTableClient client,
    required this.table,
    this.schema,
    this.appIdColumn = 'app_id',
    this.platformColumn = 'platform',
    this.environmentColumn = 'environment',
    this.selectColumns = '*',
    SupabaseRuleBuilder? ruleBuilder,
  }) : _client = client,
       ruleBuilder = ruleBuilder ?? VersionRule.fromJson;

  @override
  BackendService get backendService => BackendService.supabase;

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
    final row = await _client.fetchSingleRow(
      table: table,
      schema: schema,
      selectColumns: selectColumns,
      filters: {
        appIdColumn: appId,
        platformColumn: platform.value,
        environmentColumn: environment.value,
      },
    );

    try {
      return ruleBuilder(row);
    } on Object catch (error) {
      throw SupabaseVersionRuleException(
        'Failed to parse Supabase version rule from table "$table": $error',
      );
    }
  }
}

class SupabaseVersionRuleException implements Exception {
  final String message;

  const SupabaseVersionRuleException(this.message);

  @override
  String toString() => 'SupabaseVersionRuleException: $message';
}

abstract class SupabaseTableClient {
  Future<Map<String, dynamic>> fetchSingleRow({
    required String table,
    required String? schema,
    required String selectColumns,
    required Map<String, Object> filters,
  });
}

class _SupabaseTableClient implements SupabaseTableClient {
  final SupabaseClient client;

  const _SupabaseTableClient(this.client);

  @override
  Future<Map<String, dynamic>> fetchSingleRow({
    required String table,
    required String? schema,
    required String selectColumns,
    required Map<String, Object> filters,
  }) async {
    PostgrestFilterBuilder<dynamic> query =
        (schema == null
                ? client.from(table)
                : client.schema(schema).from(table))
            .select(selectColumns);

    for (final entry in filters.entries) {
      query = query.eq(entry.key, entry.value);
    }

    final data = await query.single() as Map;
    return Map<String, dynamic>.from(data);
  }
}

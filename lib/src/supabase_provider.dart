import 'models.dart';
import 'provider.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Converts a Supabase row into a [VersionRule].
typedef SupabaseRuleBuilder = VersionRule Function(Map<String, dynamic> json);

/// Loads version rules from a Supabase table.
///
/// The default table contract uses `app_id`, `platform`, and `environment` to
/// find one row, then parses that row with [VersionRule.fromJson].
class SupabaseVersionRuleProvider implements EnvironmentVersionRuleProvider {
  final SupabaseTableClient _client;

  /// The table that stores version rules.
  final String table;

  /// The Postgres schema containing [table], or `null` for `public`.
  final String? schema;

  /// The column containing the application identifier.
  final String appIdColumn;

  /// The column containing an [AppPlatform] value.
  final String platformColumn;

  /// The column containing an [AppEnvironment] value.
  final String environmentColumn;

  /// The columns selected from Supabase.
  final String selectColumns;

  /// Converts the selected row into a version rule.
  final SupabaseRuleBuilder ruleBuilder;

  /// Creates a provider using the initialized [Supabase] client.
  SupabaseVersionRuleProvider({
    SupabaseClient? client,
    required this.table,
    this.schema,
    this.appIdColumn = 'app_id',
    this.platformColumn = 'platform',
    this.environmentColumn = 'environment',
    this.selectColumns = '*',
    SupabaseRuleBuilder? ruleBuilder,
  }) : assert(table != '', 'table cannot be empty.'),
       _client = _SupabaseTableClient(client ?? Supabase.instance.client),
       ruleBuilder = ruleBuilder ?? VersionRule.fromJson;

  /// Creates a provider using a custom table client.
  ///
  /// This constructor is useful for tests or custom Supabase wrappers.
  SupabaseVersionRuleProvider.client({
    required SupabaseTableClient client,
    required this.table,
    this.schema,
    this.appIdColumn = 'app_id',
    this.platformColumn = 'platform',
    this.environmentColumn = 'environment',
    this.selectColumns = '*',
    SupabaseRuleBuilder? ruleBuilder,
  }) : assert(table != '', 'table cannot be empty.'),
       _client = client,
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
    late final Map<String, dynamic> row;
    try {
      row = await _client.fetchSingleRow(
        table: table,
        schema: schema,
        selectColumns: selectColumns,
        filters: {
          appIdColumn: appId,
          platformColumn: platform.value,
          environmentColumn: environment.value,
        },
      );
    } on Object catch (error) {
      throw SupabaseVersionRuleException(
        'Failed to fetch a Supabase version rule from table "$table": $error',
      );
    }

    try {
      return ruleBuilder(row);
    } on Object catch (error) {
      throw SupabaseVersionRuleException(
        'Failed to parse Supabase version rule from table "$table": $error',
      );
    }
  }
}

/// Thrown when Supabase cannot return a usable version rule.
class SupabaseVersionRuleException implements Exception {
  /// A description of the query or parsing failure.
  final String message;

  /// Creates a Supabase version-rule exception with [message].
  const SupabaseVersionRuleException(this.message);

  @override
  String toString() => 'SupabaseVersionRuleException: $message';
}

/// The Supabase table operation required by [SupabaseVersionRuleProvider].
abstract class SupabaseTableClient {
  /// Fetches one row from [table] using equality [filters].
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

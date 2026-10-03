import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'provider.dart';

/// HTTP methods supported by [EndpointVersionRuleProvider].
enum EndpointRequestMethod { get, post, put, patch }

/// Information about the request being mapped into a version rule.
class EndpointRequestContext {
  /// The application identifier sent with the request.
  final String appId;

  /// The platform being checked.
  final AppPlatform platform;

  /// The endpoint that received the request.
  final Uri endpoint;

  /// The HTTP method used for the request.
  final EndpointRequestMethod method;

  /// The deployment environment being checked.
  final AppEnvironment environment;

  /// Creates context for a custom endpoint rule builder.
  const EndpointRequestContext({
    required this.appId,
    required this.platform,
    required this.endpoint,
    required this.method,
    required this.environment,
  });
}

/// Builds a request payload for an app and platform.
typedef EndpointPayloadBuilder =
    Map<String, dynamic> Function(String appId, AppPlatform platform);

/// Builds a request payload that also includes the deployment environment.
typedef EnvironmentEndpointPayloadBuilder =
    Map<String, dynamic> Function(
      String appId,
      AppPlatform platform,
      AppEnvironment environment,
    );

/// Converts a custom endpoint response into a [VersionRule].
typedef EndpointRuleBuilder =
    VersionRule Function(
      Map<String, dynamic> json,
      EndpointRequestContext context,
    );

/// Loads version rules from a custom HTTP endpoint.
///
/// By default, requests include `appId`, `platform`, and `environment`, and the
/// response is parsed with [VersionRule.fromJson]. Builders can adapt those
/// defaults to an existing backend contract.
class EndpointVersionRuleProvider implements EnvironmentVersionRuleProvider {
  /// The backend URL used to load version rules.
  final Uri endpoint;

  /// The HTTP method used for requests.
  final EndpointRequestMethod method;

  /// Headers added to every request.
  final Map<String, String> headers;

  /// How long a request may run before timing out.
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  /// Builds a request payload when no environment-specific builder is set.
  final EndpointPayloadBuilder payloadBuilder;

  /// Optionally builds a payload with the selected environment.
  final EnvironmentEndpointPayloadBuilder? environmentPayloadBuilder;

  /// Converts a successful JSON response into a version rule.
  final EndpointRuleBuilder ruleBuilder;

  /// Creates a provider for a custom backend endpoint.
  EndpointVersionRuleProvider({
    required this.endpoint,
    this.method = EndpointRequestMethod.get,
    this.headers = const {},
    this.timeout = const Duration(seconds: 15),
    http.Client? client,
    EndpointPayloadBuilder? payloadBuilder,
    this.environmentPayloadBuilder,
    EndpointRuleBuilder? ruleBuilder,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       payloadBuilder = payloadBuilder ?? _defaultPayloadBuilder,
       ruleBuilder = ruleBuilder ?? _defaultRuleBuilder;

  @override
  BackendService get backendService => BackendService.custom;

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
    final payload =
        environmentPayloadBuilder?.call(appId, platform, environment) ??
        {...payloadBuilder(appId, platform), 'environment': environment.value};
    final context = EndpointRequestContext(
      appId: appId,
      platform: platform,
      endpoint: endpoint,
      method: method,
      environment: environment,
    );

    final response = await _sendRequest(payload).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw EndpointVersionRuleException(
        'Endpoint returned HTTP ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const EndpointVersionRuleException(
        'Endpoint response must be a JSON object.',
      );
    }

    return ruleBuilder(decoded, context);
  }

  Future<http.Response> _sendRequest(Map<String, dynamic> payload) {
    final requestHeaders = <String, String>{
      'accept': 'application/json',
      ...headers,
    };

    switch (method) {
      case EndpointRequestMethod.get:
        final uri = endpoint.replace(
          queryParameters: {
            ...endpoint.queryParameters,
            ...payload.map(
              (key, value) => MapEntry(key, value?.toString() ?? ''),
            ),
          },
        );
        return _client.get(uri, headers: requestHeaders);
      case EndpointRequestMethod.post:
        return _sendJsonWithBody(
          (uri, body, headers) =>
              _client.post(uri, body: body, headers: headers),
          payload,
          requestHeaders,
        );
      case EndpointRequestMethod.put:
        return _sendJsonWithBody(
          (uri, body, headers) =>
              _client.put(uri, body: body, headers: headers),
          payload,
          requestHeaders,
        );
      case EndpointRequestMethod.patch:
        return _sendJsonWithBody(
          (uri, body, headers) =>
              _client.patch(uri, body: body, headers: headers),
          payload,
          requestHeaders,
        );
    }
  }

  Future<http.Response> _sendJsonWithBody(
    Future<http.Response> Function(
      Uri uri,
      String body,
      Map<String, String> headers,
    )
    sender,
    Map<String, dynamic> payload,
    Map<String, String> requestHeaders,
  ) {
    return sender(endpoint, jsonEncode(payload), {
      'content-type': 'application/json',
      ...requestHeaders,
    });
  }

  /// Closes the HTTP client created by this provider.
  ///
  /// A client supplied through the constructor remains owned by the caller.
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  static Map<String, dynamic> _defaultPayloadBuilder(
    String appId,
    AppPlatform platform,
  ) {
    return {'appId': appId, 'platform': platform.value};
  }

  static VersionRule _defaultRuleBuilder(
    Map<String, dynamic> json,
    EndpointRequestContext context,
  ) {
    try {
      return VersionRule.fromJson(json);
    } on Object catch (error) {
      throw EndpointVersionRuleException(
        'Failed to parse version rule from endpoint response: $error',
      );
    }
  }
}

/// Thrown when a custom endpoint cannot return a usable version rule.
class EndpointVersionRuleException implements Exception {
  /// A description of the endpoint failure.
  final String message;

  /// Creates an endpoint exception with [message].
  const EndpointVersionRuleException(this.message);

  @override
  String toString() => 'EndpointVersionRuleException: $message';
}

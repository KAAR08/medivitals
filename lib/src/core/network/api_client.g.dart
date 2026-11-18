// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_client.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$httpClientAdapterHash() => r'676b2e4f1037bf29fe668c8287933fa795fe5e7e';

/// Null in the app (Dio's default adapter is used). Override in tests to
/// fake HTTP responses while keeping the real interceptor chain.
///
/// Copied from [httpClientAdapter].
@ProviderFor(httpClientAdapter)
final httpClientAdapterProvider = Provider<HttpClientAdapter?>.internal(
  httpClientAdapter,
  name: r'httpClientAdapterProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$httpClientAdapterHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef HttpClientAdapterRef = ProviderRef<HttpClientAdapter?>;
String _$apiClientHash() => r'5ee0a4550a1245605c943e177a82f2a11ef27035';

/// See also [apiClient].
@ProviderFor(apiClient)
final apiClientProvider = Provider<ApiClient>.internal(
  apiClient,
  name: r'apiClientProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$apiClientHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef ApiClientRef = ProviderRef<ApiClient>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

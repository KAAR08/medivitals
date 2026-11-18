// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$conversationsHash() => r'0b575b70afc7b4722301bf9e5405976f440daae9';

/// The signed-in user's conversations. Re-fetched whenever the user changes.
///
/// Copied from [conversations].
@ProviderFor(conversations)
final conversationsProvider =
    AutoDisposeFutureProvider<List<Conversation>>.internal(
  conversations,
  name: r'conversationsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$conversationsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef ConversationsRef = AutoDisposeFutureProviderRef<List<Conversation>>;
String _$conversationHash() => r'f3d48a1aab27bd78db5c889919ed0a0a4a3514ea';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// One conversation from [conversationsProvider], or null if not (yet) known.
///
/// Copied from [conversation].
@ProviderFor(conversation)
const conversationProvider = ConversationFamily();

/// One conversation from [conversationsProvider], or null if not (yet) known.
///
/// Copied from [conversation].
class ConversationFamily extends Family<Conversation?> {
  /// One conversation from [conversationsProvider], or null if not (yet) known.
  ///
  /// Copied from [conversation].
  const ConversationFamily();

  /// One conversation from [conversationsProvider], or null if not (yet) known.
  ///
  /// Copied from [conversation].
  ConversationProvider call(
    String conversationId,
  ) {
    return ConversationProvider(
      conversationId,
    );
  }

  @override
  ConversationProvider getProviderOverride(
    covariant ConversationProvider provider,
  ) {
    return call(
      provider.conversationId,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'conversationProvider';
}

/// One conversation from [conversationsProvider], or null if not (yet) known.
///
/// Copied from [conversation].
class ConversationProvider extends AutoDisposeProvider<Conversation?> {
  /// One conversation from [conversationsProvider], or null if not (yet) known.
  ///
  /// Copied from [conversation].
  ConversationProvider(
    String conversationId,
  ) : this._internal(
          (ref) => conversation(
            ref as ConversationRef,
            conversationId,
          ),
          from: conversationProvider,
          name: r'conversationProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$conversationHash,
          dependencies: ConversationFamily._dependencies,
          allTransitiveDependencies:
              ConversationFamily._allTransitiveDependencies,
          conversationId: conversationId,
        );

  ConversationProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.conversationId,
  }) : super.internal();

  final String conversationId;

  @override
  Override overrideWith(
    Conversation? Function(ConversationRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ConversationProvider._internal(
        (ref) => create(ref as ConversationRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        conversationId: conversationId,
      ),
    );
  }

  @override
  AutoDisposeProviderElement<Conversation?> createElement() {
    return _ConversationProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ConversationProvider &&
        other.conversationId == conversationId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, conversationId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin ConversationRef on AutoDisposeProviderRef<Conversation?> {
  /// The parameter `conversationId` of this provider.
  String get conversationId;
}

class _ConversationProviderElement
    extends AutoDisposeProviderElement<Conversation?> with ConversationRef {
  _ConversationProviderElement(super.provider);

  @override
  String get conversationId => (origin as ConversationProvider).conversationId;
}

String _$chatViewModelHash() => r'939658552927ddeaaa147dace4dba07ca34e8816';

abstract class _$ChatViewModel extends BuildlessAutoDisposeNotifier<ChatState> {
  late final String conversationId;

  ChatState build(
    String conversationId,
  );
}

/// See also [ChatViewModel].
@ProviderFor(ChatViewModel)
const chatViewModelProvider = ChatViewModelFamily();

/// See also [ChatViewModel].
class ChatViewModelFamily extends Family<ChatState> {
  /// See also [ChatViewModel].
  const ChatViewModelFamily();

  /// See also [ChatViewModel].
  ChatViewModelProvider call(
    String conversationId,
  ) {
    return ChatViewModelProvider(
      conversationId,
    );
  }

  @override
  ChatViewModelProvider getProviderOverride(
    covariant ChatViewModelProvider provider,
  ) {
    return call(
      provider.conversationId,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'chatViewModelProvider';
}

/// See also [ChatViewModel].
class ChatViewModelProvider
    extends AutoDisposeNotifierProviderImpl<ChatViewModel, ChatState> {
  /// See also [ChatViewModel].
  ChatViewModelProvider(
    String conversationId,
  ) : this._internal(
          () => ChatViewModel()..conversationId = conversationId,
          from: chatViewModelProvider,
          name: r'chatViewModelProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$chatViewModelHash,
          dependencies: ChatViewModelFamily._dependencies,
          allTransitiveDependencies:
              ChatViewModelFamily._allTransitiveDependencies,
          conversationId: conversationId,
        );

  ChatViewModelProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.conversationId,
  }) : super.internal();

  final String conversationId;

  @override
  ChatState runNotifierBuild(
    covariant ChatViewModel notifier,
  ) {
    return notifier.build(
      conversationId,
    );
  }

  @override
  Override overrideWith(ChatViewModel Function() create) {
    return ProviderOverride(
      origin: this,
      override: ChatViewModelProvider._internal(
        () => create()..conversationId = conversationId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        conversationId: conversationId,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<ChatViewModel, ChatState> createElement() {
    return _ChatViewModelProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatViewModelProvider &&
        other.conversationId == conversationId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, conversationId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin ChatViewModelRef on AutoDisposeNotifierProviderRef<ChatState> {
  /// The parameter `conversationId` of this provider.
  String get conversationId;
}

class _ChatViewModelProviderElement
    extends AutoDisposeNotifierProviderElement<ChatViewModel, ChatState>
    with ChatViewModelRef {
  _ChatViewModelProviderElement(super.provider);

  @override
  String get conversationId => (origin as ChatViewModelProvider).conversationId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

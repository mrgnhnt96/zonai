import 'package:scoped_deps/scoped_deps.dart';

import '../domain/message_contract_hash.dart';

final messageContractHashProvider = create<MessageContractHash>(
  MessageContractHash.new,
);

/// Used when nothing registered the provider. Lazy, like every top-level
/// `final`, so it costs nothing in the ordinary case, and shared so the
/// fallback still computes the hash once rather than once per worker spawn.
final _unscoped = MessageContractHash();

/// Falls back rather than throwing when the scope has no registration.
///
/// [bootstrap.dart] registers the provider, but not every scope that spawns a
/// worker comes from there -- generated server routes and e2e tests build
/// their own. A `StateError` from a *staleness check* would take down the
/// thing it is supposed to be protecting, which is the one failure mode a
/// guard is never allowed to have.
MessageContractHash get messageContractHash =>
    read(messageContractHashProvider, orElse: () => _unscoped);

/// Test doubles for apps built on zonai_sync. Import this only from tests:
/// it is deliberately not exported from `package:zonai_sync/zonai_sync.dart`.
///
/// [FakeZonai] is an in-memory [SyncRemote] with zonai's sync-relevant
/// semantics (server-owned `updated_at` and `rev`, whole-list 403s, 409 on a
/// duplicate id, table-level update checks), plus hooks to go offline, inject
/// failures, and interleave work with an in-flight request.
library;

import 'package:zonai_sync/src/testing/fake_zonai.dart';
import 'package:zonai_sync/zonai_sync.dart';

export 'src/testing/fake_zonai.dart';

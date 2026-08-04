import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/domain/raindrop/raindrop_sync.dart';

final raindropSyncProvider = create<RaindropSync>(() => const RaindropSync());

RaindropSync get raindropSync => read(raindropSyncProvider);

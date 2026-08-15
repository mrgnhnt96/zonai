import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/push/fcm_push_courier.dart';
import 'package:zonai/src/push/push_courier.dart';

/// The push transport. Overridden with a fake in tests — which is the entire
/// reason [PushCourier] is an interface; see its doc comment.
final pushCourierProvider = create<PushCourier>(
  () => FcmPushCourier(fileSystem: fs),
);

PushCourier get pushCourier => read(pushCourierProvider);

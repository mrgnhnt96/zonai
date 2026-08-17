import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/deps/fs.dart';
import 'package:zonai/src/push/apns_push_courier.dart';
import 'package:zonai/src/push/fcm_push_courier.dart';
import 'package:zonai/src/push/push_courier.dart';

/// The FCM transport. Overridden with a fake in tests — which is the entire
/// reason [PushCourier] is an interface; see its doc comment.
///
/// Named without a prefix for compatibility: it was the only transport, and
/// every existing override still binds it.
final pushCourierProvider = create<PushCourier>(
  () => FcmPushCourier(fileSystem: fs),
);

/// The APNs transport, used for `DevicePlatform.ios` recipients when
/// `AppConfig.push.apns` is set.
///
/// A second provider rather than a router object, because the two are
/// genuinely independent: a test can substitute one and leave the other real,
/// which is what makes "iOS went direct and Android went through FCM"
/// assertable rather than inferred.
final apnsCourierProvider = create<PushCourier>(
  () => ApnsPushCourier(fileSystem: fs),
);

PushCourier get pushCourier => read(pushCourierProvider);

PushCourier get apnsCourier => read(apnsCourierProvider);

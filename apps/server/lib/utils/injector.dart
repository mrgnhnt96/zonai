import 'package:get_it/get_it.dart';
import 'package:revali_router/revali_router.dart';

class Injector implements DI {
  Injector() : _getIt = GetIt.asNewInstance();

  final GetIt _getIt;

  @override
  T get<T extends Object>() => _getIt<T>();

  @override
  void register<T extends Object>(T Function() factory) =>
      _getIt.registerFactory<T>(factory);

  @override
  void registerInstance<T extends Object>(T instance) {
    _getIt.registerSingleton<T>(instance);
  }

  void init(void Function(GetIt getIt) init) {
    init(_getIt);
  }

  @override
  void registerFactory<T extends Object>(T Function() factory) {
    _getIt.registerFactory<T>(factory);
  }

  @override
  void registerLazySingleton<T extends Object>(T Function() factory) {
    _getIt.registerLazySingleton<T>(factory);
  }

  @override
  void registerSingleton<T extends Object>(T instance) {
    _getIt.registerSingleton<T>(instance);
  }
}

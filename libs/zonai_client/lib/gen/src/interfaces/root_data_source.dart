part of '../../interfaces.dart';

abstract interface class RootDataSource {
  const RootDataSource();

  Future<void> health();
  Stream<List<int>> favicon();
  Stream<List<int>> logo();
  Future<String> swaggerJson({String? authorization});
  Future<String> swaggerYaml({String? authorization});
}

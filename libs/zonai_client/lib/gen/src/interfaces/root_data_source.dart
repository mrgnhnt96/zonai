part of '../../interfaces.dart';

abstract interface class RootDataSource {
  const RootDataSource();

  Future<void> health();
  Stream<List<int>> favicon();
  Future<String> swaggerJson();
  Future<String> swaggerYaml();
}

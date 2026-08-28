import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/domain/dart_sdk/dart_sdk_check.dart';

final dartSdkCheckProvider = create<DartSdkCheck>(() => const DartSdkCheck());

DartSdkCheck get dartSdkCheck => read(dartSdkCheckProvider);

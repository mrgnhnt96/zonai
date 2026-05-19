import 'package:zonai_schema/src/internal/jwt_collection.dart';
import 'package:zonai_schema/src/operations/collection_operations.dart';

final class JwtOperations
    extends CollectionOperations<JwtCollection, JwtEntry> {
  JwtOperations() : super(jwts);
}

JwtOperations main() => JwtOperations();

import 'package:raindrop/raindrop.dart';

/// A transformer that transforms a secret value
///
/// Filters out the value during sanitization
abstract interface class SecretTransformer<T, O>
    extends ColumnTransformer<T, O> {
  const SecretTransformer();
}

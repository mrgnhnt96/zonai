import 'package:scoped_deps/scoped_deps.dart';
import '../domain/keyboard_input.dart';

KeyboardInput? _keyboardInput;

final keyboardInputProvider = create<KeyboardInput>(
  () => _keyboardInput ??= KeyboardInput(),
);

KeyboardInput get keyboardInput => read(keyboardInputProvider);

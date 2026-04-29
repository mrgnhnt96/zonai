import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/domain/keyboard_input.dart';

final keyboardInputProvider = create<KeyboardInput>(KeyboardInput.new);

KeyboardInput get keyboardInput => read(keyboardInputProvider);

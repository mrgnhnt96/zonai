import 'package:scoped_deps/scoped_deps.dart';
import '../domain/keyboard_input.dart';

final keyboardInputProvider = create<KeyboardInput>(KeyboardInput.new);

KeyboardInput get keyboardInput => read(keyboardInputProvider);

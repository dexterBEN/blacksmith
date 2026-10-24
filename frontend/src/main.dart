import 'package:godot_dart/godot_dart.dart';
import 'lib/core/di/service_locator.dart';

import 'godot_dart_scripts.g.dart';

void main() {
  attachScriptResolver();
  GD.print(Variant('[main] Dart scripts attached.'));
  if (Engine.singleton.isEditorHint()) return;
  setupServiceLocator();
  GD.print(Variant('[main] DI ready & scripts attached'));
}

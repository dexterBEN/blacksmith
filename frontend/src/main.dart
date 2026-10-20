import 'package:godot_dart/godot_dart.dart';
import 'lib/core/di/service_locator.dart';

import 'godot_dart_scripts.g.dart';

void main() {
  setupServiceLocator(); // inject everything with GetIt
  attachScriptResolver(); // attach script
  GD.print(Variant('[main] DI ready & scripts attached'));
}

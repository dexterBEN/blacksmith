import 'dart:ffi';
import 'package:godot_dart/godot_dart.dart';
import 'package:blacksmith_front/core/di/service_locator.dart';


import 'godot_dart_scripts.g.dart';

void main() {
  setupServiceLocator();       // inject everything with GetIt
  attachScriptResolver();      // attach script
  GD.print(Variant('[main] DI ready & scripts attached'));
}
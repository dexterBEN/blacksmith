import 'dart:async';
import 'package:godot_dart/godot_dart.dart';
import 'di/service_locator.dart' as di;

bool _installed = false;

/// The window outlives editor scenes. Scene exit cancels its observer; runtime
/// exit disposes shared services once, regardless of which editor was launched.
void installRuntimeShutdownHook(Window window) {
  if (_installed) return;
  window.treeExiting.connect(window, () {
    unawaited(di.disposeServiceLocator());
  });
  _installed = true;
}

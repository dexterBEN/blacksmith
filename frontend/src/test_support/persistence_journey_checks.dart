// Match the production resolver's file-URI identities.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:async' as async;
import 'dart:convert';
import 'dart:io';
import 'package:godot_dart/godot_dart.dart';
import 'package:http/http.dart' as http;
import '../lib/core/di/service_locator.dart' as di;
import '../lib/data/repositories/cloud_storage_repository.dart';
import '../lib/data/repositories/design_repository.dart';
import '../lib/data/repositories/resource_repository.dart';
import '../lib/data/services/cloud_services_api.dart';
import '../lib/domain/bloc/design/design_cubit.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/domain/models/resource_kind.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';
import '../lib/prototypes/isometric_3d/resource_visuals_3d.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';
import 'isometric_3d_framing_checks.dart';

final _base = Uri.parse(Platform.environment['BLACKSMITH_BACKEND_URL']!);
final _output = Platform.environment['BLACKSMITH_PERSISTENCE_OUTPUT']!;
final _phase = Platform.environment['BLACKSMITH_PERSISTENCE_PHASE']!;
final _designClient = _MetadataClient();
final _resourceClient = _MetadataClient();
final _cloudClient = _NoHttp();
late final _NoCloud _cloud;
const _position = GridPos(2, 3);

class _NoHttp extends http.BaseClient {
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls++;
    throw StateError('Cloud HTTP is forbidden.');
  }
}

class _NoCloud extends CloudStorageRepository {
  _NoCloud(CloudServicesApi api) : super(api, projectId: 'never-provision');
  int calls = 0;
  @override
  Future<String> createBucket({required int row, required int col}) {
    calls++;
    throw StateError('Provisioning is forbidden.');
  }
}

/// Real HTTP with a narrow allowlist; one deliberate real backend 404 fault.
class _MetadataClient extends http.BaseClient {
  final _real = http.Client();
  final events = <Map<String, Object>>[];
  bool failNextRead = false, closed = false;
  int posts = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _check(
        request.url.origin == _base.origin &&
            RegExp(r'^/(designs|resources|resource-types)($|/)')
                .hasMatch(request.url.path) &&
            {'GET', 'POST'}.contains(request.method),
        'Only metadata API requests are allowed.');
    if (request.method == 'POST') posts++;
    var actual = request;
    if (failNextRead &&
        request.method == 'GET' &&
        request.url.path.endsWith('/resources')) {
      failNextRead = false;
      actual = http.Request(
          'GET',
          _base.resolve(
              '/designs/ffffffff-ffff-ffff-ffff-ffffffffffff/resources'))
        ..headers.addAll(request.headers);
    }
    final response = await _real.send(actual);
    events.add({
      'method': actual.method,
      'path': actual.url.path,
      'status': response.statusCode
    });
    if (actual != request) {
      _check(response.statusCode == 404, 'Fault must be a genuine API 404.');
      GD.print(Variant('BLACKSMITH_ISSUE44_REAL_BACKEND_ERROR status=404'));
    }
    return response;
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    _real.close();
  }
}

void beforeStartup() {
  if (Engine.singleton.isEditorHint()) return;
  final api = CloudServicesApi(
      baseUrl: 'http://forbidden.invalid', client: _cloudClient);
  _cloud = _NoCloud(api);
  di.sl.registerSingleton<CloudServicesApi>(api, dispose: (api) => api.close());
  di.sl.registerSingleton<CloudStorageRepository>(_cloud);
  di.sl.registerSingleton<DesignRepository>(
      DesignRepository(baseUrl: _base.toString(), client: _designClient),
      dispose: (repository) => repository.close());
  di.sl.registerSingleton<ResourceRepository>(
      ResourceRepository(baseUrl: _base.toString(), client: _resourceClient),
      dispose: (repository) => repository.close());
}

void afterStartup() {
  if (Engine.singleton.isEditorHint()) return;
  async.Timer.run(() async {
    final tree = Engine.singleton.getMainLoop()! as SceneTree;
    try {
      await _until(() => tree.getCurrentScene() != null);
      var scene = tree.getCurrentScene()!;
      final cubit = di.sl<DesignCubit>();
      final grid = di.sl<IsomapGridBloc>();
      _check(cubit.state.active == null && grid.state.tiles.isEmpty,
          'A fresh application must lose all previous in-memory editor state.');
      tree.getRoot()!
        ..setContentScaleMode(WindowContentScaleMode.viewport)
        ..setContentScaleAspect(WindowContentScaleAspect.keep)
        ..setContentScaleSize(Vector2i.fromXY(1280, 800));
      scene.getViewport()!
        ..setDisableInput(false)
        ..call('notify_mouse_entered');
      await _settle(scene);
      checkEditorFraming(scene);
      if (_phase == 'save') {
        await _click(
            scene, _header(scene, 'NewDesign').getGlobalRect().getCenter());
        _input(scene).setText(
            'Blacksmith Issue44 smoke ${DateTime.now().toUtc().microsecondsSinceEpoch}');
        await _settle(scene);
        await _click(scene, _dialogButton(scene).getGlobalRect().getCenter());
        await _until(() => cubit.state.active != null && !cubit.state.pending);
        await _select(scene);
        await _choose(scene, Workspace3D.catalog, ResourceKind.cloudStorage);
        _check(cubit.state.canSave && !cubit.state.saved,
            'Placement must start unsaved.');
        await _capture(scene, 'before_save.png');
        _resourceClient.failNextRead = true;
        await _click(
            scene, _header(scene, 'SaveDesign').getGlobalRect().getCenter());
        await _until(() =>
            !cubit.state.pending &&
            cubit.state.persistenceMessage.contains('HTTP 404'));
        _check(
            !cubit.state.saved &&
                grid.state.tiles[_position] == ResourceKind.cloudStorage &&
                _resourceClient.posts == 0,
            'Failed real backend read preserves the unsaved cube.');
        await _capture(scene, 'save_error.png');
        await _click(
            scene, _header(scene, 'SaveDesign').getGlobalRect().getCenter());
        await _until(() => cubit.state.saved && !cubit.state.pending);
        await _click(
            scene, _header(scene, 'SaveDesign').getGlobalRect().getCenter());
        _check(_resourceClient.posts == 1 && _designClient.posts == 1,
            'One Design and one Resource POST; repeated Save is disabled.');
        final records = await di
            .sl<ResourceRepository>()
            .listForDesign(cubit.state.active!.id);
        _check(records.length == 1 && records.single.position == _position,
            'Independent API read-back.');
        await File('$_output/journey.json').writeAsString(jsonEncode({
          'design_id': cubit.state.active!.id,
          'design_name': cubit.state.active!.name,
          'resource_id': records.single.id,
          'x': 3,
          'y': 2,
          'type': records.single.type,
          'count': records.length,
          'save_pid': pid
        }));
        await _capture(scene, 'saved.png');
      } else {
        final saved =
            jsonDecode(await File('$_output/journey.json').readAsString())
                as Map<String, dynamic>;
        _check(saved['save_pid'] != pid,
            'Reopen must run in a different complete Godot process.');
        await _click(
            scene, _header(scene, 'OpenDesign').getGlobalRect().getCenter());
        _input(scene).setText(saved['design_id'] as String);
        await _settle(scene);
        await _click(scene, _dialogButton(scene).getGlobalRect().getCenter());
        await _until(() =>
            cubit.state.active?.id == saved['design_id'] && cubit.state.saved);
        _check(
            grid.state.tiles.length == 1 &&
                grid.state.tiles[_position] == ResourceKind.cloudStorage,
            'Reopen hydrates the exact original logical tile.');
        await _select(scene);
        _cube(scene);
        await _capture(scene, 'after_relaunch.png');
        await _choose(scene, Workspace3D.choices, ResourceKind.computeEngine);
        _check(!cubit.state.saved && !cubit.state.canSave,
            'Replacement stays local and unsupported for persistence.');
        await _choose(scene, Workspace3D.choices, ResourceKind.cloudStorage);
        _check(cubit.state.saved,
            'Restoring the confirmed local snapshot requires no write.');
        final previous = scene.getInstanceId();
        final oldCube = _cube(scene).getInstanceId();
        _check(tree.reloadCurrentScene() == GDError.ok,
            'Scene reload must succeed.');
        await _until(() => tree.getCurrentScene()!.getInstanceId() != previous);
        await _settle(tree.getCurrentScene()!);
        scene = tree.getCurrentScene()!;
        _check(
            !GD.isInstanceIdValid(oldCube) &&
                scene.getNodeT<Node3D>('ResourceRoot')!.getChildCount() == 1,
            'Reinitialization frees old meshes and restores only one cube.');
        final records = await di
            .sl<ResourceRepository>()
            .listForDesign(cubit.state.active!.id);
        _check(
            records.length == 1 &&
                records.single.id == saved['resource_id'] &&
                records.single.position == _position &&
                _resourceClient.posts == 0 &&
                _designClient.posts == 0,
            'Open/reload/local edits must not create another database row.');
        await File('$_output/reopened.json').writeAsString(jsonEncode({
          ...saved,
          'open_pid': pid,
          'restored': true,
          'count': records.length,
          'resource_posts': _resourceClient.posts,
          'design_posts': _designClient.posts
        }));
      }
      checkEditorFraming(scene);
      _check(_cloud.calls == 0 && _cloudClient.calls == 0,
          'Zero cloud provisioning and cloud HTTP.');
      await File('$_output/$_phase-http.json').writeAsString(
          jsonEncode([..._designClient.events, ..._resourceClient.events]));
      tree.getRoot()!.emitSignal('tree_exiting');
      await _until(() =>
          cubit.isClosed &&
          grid.isClosed &&
          _resourceClient.closed &&
          _designClient.closed);
      GD.print(Variant('BLACKSMITH_PERSISTENCE_${_phase.toUpperCase()}_PASSED '
          'real_api=true row=2 col=3 cloud_calls=0 cloud_http=0 pid=$pid'));
      tree.quit();
    } catch (error, stack) {
      GD.print(Variant('BLACKSMITH_PERSISTENCE_FAILED: $error\n$stack'));
      tree.quit(exitCode: 1);
    }
  });
}

Button _header(Node scene, String name) =>
    scene.getNodeT<Button>('${Workspace3D.header}/Rows/Actions/$name')!;
LineEdit _input(Node scene) =>
    scene.getNodeT<LineEdit>('DesignLayer/DesignControls/Shade/Dialog/Name')!;
Button _dialogButton(Node scene) =>
    scene.getNodeT<Button>('DesignLayer/DesignControls/Shade/Dialog/Create')!;
Node3D _cube(Node scene) {
  final cube = scene.getNodeT<Node3D>('ResourceRoot/Resource_2_3')!;
  final p = const GridLayout3D().worldPosition(_position);
  _check(
      cube.getSceneFilePath() ==
              resourceVisuals3D[ResourceKind.cloudStorage]!.scenePath &&
          (cube.getPosition() - Vector3(x: p.x, y: .12, z: p.z)).length < 1e-5,
      'Existing Cloud Storage scene must occupy row 2 / column 3.');
  return cube;
}

Future<void> _select(Node scene) async {
  final p = const GridLayout3D().worldPosition(_position);
  await _click(
      scene,
      Workspace3D.project(
          scene, (scene as Node3D).toGlobal(Vector3(x: p.x, y: .12, z: p.z))));
}

Future<void> _choose(Node scene, String group, ResourceKind kind) => _click(
    scene,
    scene
        .getNodeT<Button>('$group/${resourceVisuals3D[kind]!.buttonName}')!
        .getGlobalRect()
        .getCenter());
void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 150; i++) {
    if (condition()) return;
    await async.Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Timed out waiting for the native persistence journey.');
}

Future<void> _settle(Node scene) async {
  await RenderingServer.singleton.framePostDraw.asFuture(scene);
  await async.Future<void>.delayed(const Duration(milliseconds: 150));
  await RenderingServer.singleton.framePostDraw.asFuture(scene);
}

Future<void> _capture(Node scene, String name) async {
  await _settle(scene);
  _check(
      scene
              .getViewport()!
              .getTexture()!
              .getImage()!
              .savePng('$_output/$name') ==
          GDError.ok,
      'Save actual unmodified native Godot rendering.');
}

Future<void> _click(Node scene, Vector2 point) async {
  final viewport = scene.getViewport()!;
  viewport.pushInput(InputEventMouseMotion()..setPosition(point),
      inLocalCoords: true);
  await _settle(scene);
  for (final pressed in [true, false]) {
    viewport.pushInput(
        InputEventMouseButton()
          ..setPosition(point)
          ..setGlobalPosition(point)
          ..setButtonIndex(MouseButton.left)
          ..setPressed(pressed),
        inLocalCoords: true);
    await _settle(scene);
  }
}

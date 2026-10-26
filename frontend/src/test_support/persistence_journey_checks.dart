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
import '../lib/domain/models/placed_resource.dart';
import '../lib/domain/models/resource_configuration.dart';
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
const _secondPosition = GridPos(4, 1);

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
  int posts = 0, puts = 0;
  int losePostNumber = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _check(
        request.url.origin == _base.origin &&
            RegExp(r'^/(designs|resources|resource-types)($|/)')
                .hasMatch(request.url.path) &&
            (request.method == 'GET' ||
                request.method == 'POST' &&
                    {'/resources', '/designs'}.contains(request.url.path) ||
                request.method == 'PUT' &&
                    RegExp(r'^/designs/[0-9a-f-]+/resources/[0-9a-f-]+$')
                        .hasMatch(request.url.path)),
        'Only metadata API requests are allowed.');
    if (request.method == 'POST') posts++;
    if (request.method == 'PUT') puts++;
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
      GD.print(Variant('BLACKSMITH_ISSUE53_REAL_BACKEND_ERROR status=404'));
    }
    if (request.method == 'POST' &&
        request.url.path == '/resources' &&
        posts == losePostNumber) {
      await response.stream.drain<void>();
      throw http.ClientException(
          'Injected lost response after the real Resource commit.');
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
        _enter(scene,
            'Blacksmith Issue53 smoke ${DateTime.now().toUtc().microsecondsSinceEpoch}');
        await _settle(scene);
        await _click(scene, _dialogButton(scene).getGlobalRect().getCenter());
        await _until(() => cubit.state.active != null && !cubit.state.pending);
        await _select(scene);
        await _choose(scene, Workspace3D.catalog, ResourceKind.cloudStorage);
        await _select(scene, _secondPosition);
        await _choose(scene, Workspace3D.choices, ResourceKind.cloudStorage);
        _check(
            cubit.state.canSave &&
                !cubit.state.saved &&
                grid.state.resources.length == 2,
            'Both palette entry points must create distinct unsaved placements.');
        final originalNodes = {
          for (final pos in [_position, _secondPosition])
            pos: _cube(scene, pos).getInstanceId()
        };
        await _capture(scene, 'before_save.png');
        _resourceClient.failNextRead = true;
        await _click(
            scene, _header(scene, 'SaveDesign').getGlobalRect().getCenter());
        await _until(() =>
            !cubit.state.pending &&
            cubit.state.persistenceMessage.contains('HTTP 404'));
        _check(
            !cubit.state.saved &&
                grid.state.resources.length == 2 &&
                _resourceClient.posts == 0,
            'Failed real preflight must preserve both cubes without a write.');
        await _capture(scene, 'save_error.png');
        _resourceClient.losePostNumber = 2;
        await _click(
            scene, _header(scene, 'SaveDesign').getGlobalRect().getCenter());
        await _until(() => !cubit.state.pending && cubit.state.saveUncertain);
        _check(
            !cubit.state.saved &&
                _resourceClient.posts == 2 &&
                grid.state.resources[_position]!.id != null &&
                grid.state.resources[_secondPosition]!.id == null,
            'A is confirmed; B committed but its lost response must not falsely mark the Design saved.');
        await _capture(scene, 'save_unknown.png');
        await _click(
            scene, _header(scene, 'SaveDesign').getGlobalRect().getCenter());
        await _until(() => cubit.state.saved && !cubit.state.pending);
        _check(_resourceClient.posts == 2 && _resourceClient.puts == 0,
            'Check Save is read-only and must not create another identity.');
        await _click(
            scene, _header(scene, 'SaveDesign').getGlobalRect().getCenter());
        _check(_resourceClient.posts == 2 && _designClient.posts == 1,
            'Repeated unchanged Save must be a no-op.');
        final repository = di.sl<ResourceRepository>();
        var records = await repository.listForDesign(cubit.state.active!.id);
        _check(
            records.length == 2 &&
                records.map((r) => r.id).toSet().length == 2 &&
                records.every((r) => r.configuration == null),
            'Palette Save must not fabricate configuration.');
        _check(
            originalNodes.entries
                .every((e) => _cube(scene, e.key).getInstanceId() == e.value),
            'Confirming server metadata must preserve both mesh nodes.');
        await _capture(scene, 'saved.png');

        // Explicit test data, never defaults inserted by the production palette.
        final first = records.singleWhere((r) => r.position == _position);
        final configured = PlacedResource.fromPersisted(first)
            .withConfiguration(ResourceConfiguration(schemaVersion: 1, values: {
          'projectId': 'example-project-123',
          'bucketName': 'blacksmith-native-fixture',
          'location': 'europe-west9'
        }));
        await repository.writeConfigured(
            cubit.state.active!.id, _position, configured);
        await _open(scene, cubit, cubit.state.active!.id);
        _check(
            grid.state.resources[_position]!.configuration ==
                    configured.configuration &&
                originalNodes.entries.every(
                    (e) => _cube(scene, e.key).getInstanceId() == e.value),
            'Configuration-only aggregate Open must preserve existing cube nodes.');
        records = await repository.listForDesign(cubit.state.active!.id);
        final window = tree.getRoot()!;
        window
          ..setSize(Vector2i.fromXY(960, 640))
          ..setContentScaleSize(Vector2i.fromXY(960, 640));
        await _settle(scene);
        checkEditorFraming(scene);
        _check(
            window.getSize().x >= 960 &&
                window.getSize().y >= 640 &&
                scene.getNodeT<Node3D>('ResourceRoot')!.getChildCount() == 2,
            'The configured desktop minimum preserves the two resources and board framing.');
        await _capture(scene, 'minimum_two_resources.png');
        window
          ..setSize(Vector2i.fromXY(1152, 648))
          ..setContentScaleSize(Vector2i.fromXY(1280, 800));
        await _settle(scene);
        await File('$_output/journey.json').writeAsString(jsonEncode({
          'design_id': cubit.state.active!.id,
          'design_name': cubit.state.active!.name,
          'resources': [
            for (final r in records)
              {
                'id': r.id,
                'x': r.x,
                'y': r.y,
                'revision': r.revision,
                'configured': r.configuration != null
              }
          ],
          'count': records.length,
          'save_pid': pid,
          'resource_posts': _resourceClient.posts,
          'fixture_puts': _resourceClient.puts
        }));
      } else {
        final saved =
            jsonDecode(await File('$_output/journey.json').readAsString())
                as Map<String, dynamic>;
        _check(saved['save_pid'] != pid,
            'Reopen must run in another complete Godot process.');
        await _open(scene, cubit, saved['design_id'] as String);
        _check(
            grid.state.resources.length == 2 &&
                grid.state.tiles[_position] == ResourceKind.cloudStorage &&
                grid.state.tiles[_secondPosition] == ResourceKind.cloudStorage,
            'Both original tiles must restore.');
        for (final entry in saved['resources'] as List<dynamic>) {
          final r = entry as Map<String, dynamic>;
          final restored =
              grid.state.resources[GridPos(r['y'] as int, r['x'] as int)]!;
          _check(
              restored.id == r['id'] &&
                  restored.revision == r['revision'] &&
                  (restored.configuration != null) == r['configured'],
              'Restore exact identities, revisions and optional configurations.');
        }
        _check(
            grid.state.resources[_position]!.configuration!
                    .values['bucketName'] ==
                'blacksmith-native-fixture',
            'Persisted explicit configuration survives full application restart.');
        final nodes = {
          for (final pos in [_position, _secondPosition])
            pos: _cube(scene, pos).getInstanceId()
        };
        await _capture(scene, 'after_relaunch.png');
        await _open(scene, cubit, saved['design_id'] as String);
        _check(
            nodes.entries
                .every((e) => _cube(scene, e.key).getInstanceId() == e.value),
            'Repeated Open must not duplicate or rebuild unchanged cubes.');
        await _select(scene);
        await _choose(scene, Workspace3D.choices, ResourceKind.computeEngine);
        _check(
            grid.state.tiles[_position] == ResourceKind.cloudStorage &&
                cubit.state.saved,
            'Persisted kind replacement is blocked instead of silently discarding saved identity/configuration.');
        final previous = scene.getInstanceId();
        _check(tree.reloadCurrentScene() == GDError.ok,
            'Scene reload must succeed.');
        await _until(() =>
            tree.getCurrentScene() != null &&
            tree.getCurrentScene()!.getInstanceId() != previous);
        await _settle(tree.getCurrentScene()!);
        scene = tree.getCurrentScene()!;
        _check(
            nodes.values.every((node) => !GD.isInstanceIdValid(node)) &&
                scene.getNodeT<Node3D>('ResourceRoot')!.getChildCount() == 2,
            'Scene disposal frees old nodes and restores exactly two cubes from shared state.');
        _check(
            _resourceClient.posts == 0 &&
                _resourceClient.puts == 0 &&
                _designClient.posts == 0,
            'Open/repeated Open/reload must issue no write.');
        await File('$_output/reopened.json').writeAsString(jsonEncode({
          ...saved,
          'open_pid': pid,
          'restored': true,
          'count': grid.state.resources.length,
          'resource_posts': _resourceClient.posts,
          'resource_puts': _resourceClient.puts,
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
          'real_api=true resources=2 cloud_calls=0 cloud_http=0 pid=$pid'));
      tree.quit();
    } catch (error, stack) {
      GD.print(Variant('BLACKSMITH_PERSISTENCE_FAILED: $error\n$stack'));
      tree.quit(exitCode: 1);
    }
  });
}

Future<void> _open(Node scene, DesignCubit cubit, String id) async {
  await _click(scene, _header(scene, 'OpenDesign').getGlobalRect().getCenter());
  _enter(scene, id);
  await _settle(scene);
  await _click(scene, _dialogButton(scene).getGlobalRect().getCenter());
  await _until(() =>
      !cubit.state.dialogOpen &&
      cubit.state.active?.id == id &&
      cubit.state.saved &&
      !cubit.state.pending);
}

void _enter(Node scene, String value) {
  final field = _input(scene);
  field.setText(value);
  // Programmatic set_text does not emit the signal produced by actual typing.
  field.textChanged.emit(value);
}

Button _header(Node scene, String name) =>
    scene.getNodeT<Button>('${Workspace3D.header}/Rows/Actions/$name')!;
LineEdit _input(Node scene) =>
    scene.getNodeT<LineEdit>('DesignLayer/DesignControls/Shade/Dialog/Name')!;
Button _dialogButton(Node scene) =>
    scene.getNodeT<Button>('DesignLayer/DesignControls/Shade/Dialog/Create')!;
Node3D _cube(Node scene, [GridPos position = _position]) {
  final cube = scene.getNodeT<Node3D>(
      'ResourceRoot/Resource_${position.row}_${position.col}')!;
  final p = const GridLayout3D().worldPosition(position);
  _check(
      cube.getSceneFilePath() ==
              resourceVisuals3D[ResourceKind.cloudStorage]!.scenePath &&
          (cube.getPosition() - Vector3(x: p.x, y: .12, z: p.z)).length < 1e-5,
      'Existing Cloud Storage scene must occupy its exact logical tile.');
  return cube;
}

Future<void> _select(Node scene, [GridPos position = _position]) async {
  final p = const GridLayout3D().worldPosition(position);
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

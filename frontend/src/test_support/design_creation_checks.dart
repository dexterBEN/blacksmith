// Match the production resolver's file-URI library identities.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:async' as async;
import 'dart:convert';
import 'dart:io';
import 'package:godot_dart/godot_dart.dart';
import 'workspace_test_input.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';
import 'package:http/http.dart' as http;
import '../lib/core/di/service_locator.dart' as di;
import '../lib/data/repositories/design_repository.dart';
import '../lib/data/repositories/cloud_storage_repository.dart';
import '../lib/data/services/cloud_services_api.dart';
import '../lib/domain/bloc/design/design_cubit.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/domain/models/resource_kind.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';
import 'isometric_3d_framing_checks.dart';

final _live = Platform.environment['BLACKSMITH_DESIGN_LIVE'] == '1';
final _baseUrl =
    Platform.environment['BLACKSMITH_BACKEND_URL'] ?? di.defaultBackendUrl;
final _client = _DesignClient();
final _cloudClient = _NoCloudClient();
late final _NoCloudRepository _cloud;
const _fixtureId = '12345678-1234-1234-1234-123456789abc';

class _NoCloudClient extends http.BaseClient {
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls++;
    throw StateError('Cloud HTTP forbidden.');
  }
}

class _NoCloudRepository extends CloudStorageRepository {
  _NoCloudRepository(CloudServicesApi api)
      : super(api, projectId: 'never-provision');
  int calls = 0;
  @override
  Future<String> createBucket({required int row, required int col}) {
    calls++;
    throw StateError('Provisioning forbidden.');
  }
}

class _DesignClient extends http.BaseClient {
  final http.Client _real = http.Client();
  String mode = 'forbidden';
  int posts = 0, gets = 0;
  int? livePostStatus, liveGetStatus;
  final pending = async.Completer<http.StreamedResponse>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final expected = Uri.parse(_baseUrl);
    _check(
        request.url.origin == expected.origin &&
            (request.method == 'POST' &&
                    request.url.path == '${expected.path}/designs' ||
                request.method == 'GET' &&
                    request.url.path.startsWith('${expected.path}/designs/')),
        'Only configured Design endpoints may be contacted.');
    if (request.method == 'POST') {
      posts++;
    } else {
      gets++;
    }
    if (mode == 'pending') return pending.future;
    if (mode == 'live') {
      return _real.send(request).then((response) {
        if (request.method == 'POST') {
          livePostStatus = response.statusCode;
        } else {
          liveGetStatus = response.statusCode;
        }
        return response;
      });
    }
    if (mode == 'success') {
      final name = jsonDecode((request as http.Request).body)['name'];
      return async.Future.value(
          response(201, jsonEncode({'id': _fixtureId, 'name': name})));
    }
    throw StateError('Unexpected Design I/O: $mode');
  }

  static http.StreamedResponse response(int status, String body) =>
      http.StreamedResponse(Stream.value(utf8.encode(body)), status,
          headers: {'content-type': 'application/json; charset=utf-8'});
  @override
  void close() {
    _real.close();
  }
}

void beforeStartup() {
  if (Engine.singleton.isEditorHint()) return;
  final api = CloudServicesApi(
      baseUrl: 'http://forbidden.invalid', client: _cloudClient);
  _cloud = _NoCloudRepository(api);
  di.sl.registerSingleton<CloudServicesApi>(api, dispose: (a) => a.close());
  di.sl.registerSingleton<CloudStorageRepository>(_cloud);
  di.sl.registerSingleton<DesignRepository>(
      DesignRepository(baseUrl: _baseUrl, client: _client),
      dispose: (r) => r.close());
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
      scene.getViewport()!
        ..setDisableInput(false)
        ..call('notify_mouse_entered');
      await _pause();
      Button action(String name) =>
          scene.getNodeT<Button>('${Workspace3D.header}/Rows/Actions/$name')!;
      Button dialogButton(String name) => scene
          .getNodeT<Button>('DesignLayer/DesignControls/Shade/Dialog/$name')!;
      LineEdit input() => scene
          .getNodeT<LineEdit>('DesignLayer/DesignControls/Shade/Dialog/Name')!;
      Label feedback() => scene
          .getNodeT<Label>('DesignLayer/DesignControls/Shade/Dialog/Feedback')!;
      Future<void> open() async {
        await _click(scene, action('NewDesign').getGlobalRect().getCenter());
        await _until(() => cubit.state.dialogOpen);
      }

      void enter(String name) {
        input().setText(name);
        input()
            .textChanged
            .emit(name); // Godot set_text intentionally emits no signal.
      }

      Future<void> select(GridPos pos) async {
        await dismissWorkspaceMenus(scene);
        final p = const GridLayout3D().worldPosition(pos);
        final screen = Workspace3D.project(
            scene, (scene as Node3D).toGlobal(Vector3(x: p.x, y: .12, z: p.z)));
        await _click(scene, screen);
        _check(grid.state.selected == pos, '3D selection remains functional.');
      }

      Future<void> place() async {
        await select(const GridPos(0, 0));
        if (!scene.getNodeT<Control>(Workspace3D.sidebar)!.isVisibleInTree()) {
          await openWorkspaceAction(scene, Workspace3D.libraryToggle);
        }
        await _click(
            scene,
            scene
                .getNodeT<Button>('${Workspace3D.catalog}/ComputeEngine')!
                .getGlobalRect()
                .getCenter());
        await confirmResourceChoice(scene);
        _check(
            grid.state.tiles[const GridPos(0, 0)] == ResourceKind.computeEngine,
            'Placement remains local.');
      }

      await open();
      _check(dialogButton('Create').isDisabled(), 'Empty name cannot submit.');
      enter('   ');
      await _pause();
      _check(
          dialogButton('Create').isDisabled() &&
              feedback().getText().isNotEmpty,
          'Invalid name shows feedback without a request.');
      await _click(scene, dialogButton('Cancel').getGlobalRect().getCenter());
      _check(!cubit.state.dialogOpen && _client.posts == 0,
          'Cancel sends no request.');
      await place();
      final before = grid.state;
      await open();
      enter('Blacksmith issue39 native check');
      await _pause();
      _check(
          dialogButton('Create').isDisabled(), 'Discard consent is required.');
      _check(
          scene
              .getNodeT<Button>('${Workspace3D.catalog}/CloudStorage')!
              .isDisabled(),
          'Modal blocks keyboard and pointer placement behind the dialog.');
      await _capture(scene, 'new_design_dialog.png');
      final discard = scene.getNodeT<CheckButton>(
          'DesignLayer/DesignControls/Shade/Dialog/Discard')!;
      await _click(scene, discard.getGlobalRect().getCenter());
      _client.mode = 'pending';
      await _click(scene, dialogButton('Create').getGlobalRect().getCenter());
      _check(
          cubit.state.pending &&
              cubit.state.active == null &&
              dialogButton('Create').isDisabled() &&
              dialogButton('Cancel').isDisabled() &&
              !input().isEditable(),
          'Pending is visible; no premature active Design.');
      await _click(scene, dialogButton('Create').getGlobalRect().getCenter());
      await cubit.submit();
      cubit.cancel();
      _check(_client.posts == 1 && grid.state == before,
          'Duplicate/cancel cannot replay a pending POST.');
      _client.pending
          .complete(_DesignClient.response(503, 'SECRET_SERVER_DIAGNOSTIC'));
      await _until(() => cubit.state.status == DesignStatus.failure);
      await _pause();
      _check(
          feedback().getText().contains('HTTP 503') &&
              !feedback().getText().contains('SECRET') &&
              grid.state == before &&
              cubit.state.active == null,
          'Visible sanitized failure preserves unsaved work.');
      await _capture(scene, 'new_design_error.png');
      await _click(scene, dialogButton('Cancel').getGlobalRect().getCenter());
      _check(grid.state == before && !cubit.state.dialogOpen,
          'Error can be dismissed without losing work.');
      await open();
      final testName =
          'Blacksmith issue39 smoke ${DateTime.now().toUtc().millisecondsSinceEpoch}';
      enter(testName);
      await _pause();
      await _click(scene, discard.getGlobalRect().getCenter());
      _client.mode = _live ? 'live' : 'success';
      await _click(scene, dialogButton('Create').getGlobalRect().getCenter());
      await _until(() =>
          cubit.state.active != null &&
          !cubit.state.dialogOpen &&
          grid.state.tiles.isEmpty);
      final design = cubit.state.active!;
      _check(
          design.name == testName &&
              grid.state.selected == null &&
              scene
                  .getNodeT<Label>('${Workspace3D.header}/Rows/ActiveDesign')!
                  .getText()
                  .contains(testName),
          'Only API-confirmed success sets the active Design and empties the logical grid.');
      if (_live) {
        final read = await di.sl<DesignRepository>().getById(design.id);
        _check(read == design, 'Real API read-back matches frontend ID/name.');
      }
      await _pause();
      await _capture(scene, 'new_design_success.png');
      final evidence = {
        'live': _live,
        'id': design.id,
        'name': design.name,
        'real_post_count': _live ? 1 : 0,
        'real_get_count': _client.gets,
        'post_status': _client.livePostStatus,
        'get_status': _client.liveGetStatus,
        'cloud_calls': _cloud.calls,
        'cloud_http': _cloudClient.calls
      };
      File('${Platform.environment['BLACKSMITH_DESIGN_OUTPUT']}/design_result.json')
          .writeAsStringSync(
              const JsonEncoder.withIndent('  ').convert(evidence));
      // Active Design and empty grid survive reload; old controls unsubscribe.
      tree.reloadCurrentScene();
      await _pause();
      await _pause();
      await _until(() =>
          tree.getCurrentScene() != null && tree.getCurrentScene() != scene);
      scene = tree.getCurrentScene()!;
      _check(
          identical(cubit, di.sl<DesignCubit>()) &&
              cubit.state.active == design,
          'Reload reuses shared Design state.');
      scene.getViewport()!
        ..setDisableInput(false)
        ..call('notify_mouse_entered');
      await place();
      checkEditorFraming(scene);
      await open();
      await _click(scene, dialogButton('Cancel').getGlobalRect().getCenter());
      _check(
          _cloud.calls == 0 &&
              _cloudClient.calls == 0 &&
              _client.posts == 2 &&
              _client.gets == (_live ? 1 : 0),
          'One deliberate success POST; zero provisioning.');
      tree.getRoot()!.treeExiting.emit();
      await _until(() => cubit.isClosed && grid.isClosed);
      GD.print(Variant(
          'BLACKSMITH_DESIGN_UI_PASSED live=$_live cancel=true validation=true '
          'duplicate_guard=true active=true discard_after_success=true reload=true cloud_calls=0'));
      tree.quit();
    } catch (error, stack) {
      final scene = tree.getCurrentScene();
      if (scene != null) await _capture(scene, 'failure.png');
      GD.print(Variant('BLACKSMITH_DESIGN_UI_FAILED: $error\n$stack'));
      tree.quit(exitCode: 1);
    }
  });
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _pause() =>
    async.Future<void>.delayed(const Duration(milliseconds: 150));
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 120; i++) {
    if (condition()) return;
    await _pause();
  }
  throw StateError('Timed out waiting for Design UI/state.');
}

Future<void> _capture(Node scene, String filename) async {
  await RenderingServer.singleton.framePostDraw.asFuture(scene);
  final result = scene
      .getViewport()!
      .getTexture()!
      .getImage()!
      .savePng('${Platform.environment['BLACKSMITH_DESIGN_OUTPUT']}/$filename');
  _check(result == GDError.ok, 'Save actual Godot viewport.');
}

Future<void> _click(Node scene, Vector2 point) async {
  final viewport = scene.getViewport()!;
  viewport.pushInput(InputEventMouseMotion()..setPosition(point),
      inLocalCoords: true);
  // Godot refreshes GUI hover between frames. Let the actual pointer target
  // settle before pressing, including on slow software-rendered VM frames.
  await RenderingServer.singleton.framePostDraw.asFuture(scene);
  await _pause();
  for (final pressed in [true, false]) {
    viewport.pushInput(
        InputEventMouseButton()
          ..setPosition(point)
          ..setGlobalPosition(point)
          ..setButtonIndex(MouseButton.left)
          ..setPressed(pressed),
        inLocalCoords: true);
    await _pause();
    await RenderingServer.singleton.framePostDraw.asFuture(scene);
  }
}

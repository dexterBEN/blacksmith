// Match the production resolver's file-URI identities.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:async' as async;
import 'dart:convert';
import 'dart:io';
import 'package:godot_dart/godot_dart.dart';
import 'workspace_test_input.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';
import '../lib/core/di/service_locator.dart' as di;
import '../lib/data/repositories/design_repository.dart';
import '../lib/data/repositories/resource_repository.dart';
import '../lib/domain/bloc/design/design_cubit.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/domain/models/resource_kind.dart';
import '../lib/domain/models/resource_configuration.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';
import '../lib/prototypes/isometric_3d/resource_visuals_3d.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';
import 'isometric_3d_framing_checks.dart';

final _base = Uri.parse(Platform.environment['BLACKSMITH_BACKEND_URL']!);
final _output = Platform.environment['BLACKSMITH_PERSISTENCE_OUTPUT']!;
final _phase = Platform.environment['BLACKSMITH_PERSISTENCE_PHASE']!;
const _position = GridPos(2, 3), _secondPosition = GridPos(4, 1);
const _fixtureToken = 'fixture-only-never-authorizes-real-cloud-0000';
final _client = _DeploymentClient();

class _DeploymentClient extends http.BaseClient {
  final real = http.Client();
  final events = <Map<String, Object>>[];
  bool loseDeploymentResponse = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _check(
        request.url.origin == _base.origin &&
            RegExp(r'^/(designs|resources|resource-types)($|/)')
                .hasMatch(request.url.path),
        'Only the dedicated API is reachable; legacy cloud route is forbidden.');
    final response = await real.send(request);
    events.add({
      'method': request.method,
      'path': request.url.path,
      'status': response.statusCode
    });
    if (loseDeploymentResponse &&
        {'PUT', 'POST'}.contains(request.method) &&
        request.url.path.contains('/deployments/')) {
      loseDeploymentResponse = false;
      await response.stream.drain<void>();
      throw http.ClientException(
          'Injected lost response after the durable deployment intent.');
    }
    return response;
  }

  @override
  void close() => real.close();
}

Future<Map<String, dynamic>> _stats() async {
  final response = await http.get(_base.resolve('/__test/deployment-provider'));
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  _check(body['fakeProvider'] == true, 'Only an injected fake may be tested.');
  return body;
}

void beforeStartup() {
  if (Engine.singleton.isEditorHint()) return;
  di.sl.registerSingleton<DesignRepository>(
      DesignRepository(baseUrl: _base.toString(), client: _client));
  di.sl.registerSingleton<ResourceRepository>(ResourceRepository(
      baseUrl: _base.toString(),
      client: _client,
      deploymentToken: _fixtureToken));
}

void afterStartup() {
  if (Engine.singleton.isEditorHint()) return;
  async.Timer.run(() async {
    final tree = Engine.singleton.getMainLoop()! as SceneTree;
    try {
      tree.getRoot()!
        ..setFlag(WindowFlags.flagMousePassthrough, true)
        ..setFlag(WindowFlags.flagNoFocus, true);
      await _until(() => tree.getCurrentScene() != null);
      final scene = tree.getCurrentScene()!;
      final cubit = di.sl<DesignCubit>();
      final grid = di.sl<IsomapGridBloc>();
      _check(cubit.state.active == null && grid.state.resources.isEmpty,
          'A new process starts with no remembered Design.');
      final initial = await _stats();
      tree.getRoot()!
        ..setContentScaleMode(WindowContentScaleMode.viewport)
        ..setContentScaleAspect(WindowContentScaleAspect.keep)
        ..setContentScaleSize(Vector2i.fromXY(1152, 648));
      scene.getViewport()!
        ..setDisableInput(false)
        ..call('notify_mouse_entered');
      await _settle(scene);
      if (_phase == 'save') {
        _check(initial['creates'] == 0, 'Fresh fake fixture required.');
        await _click(
            scene, _header(scene, 'NewDesign').getGlobalRect().getCenter());
        _enter(scene, 'Blacksmith Issue58 fake deployment');
        await _settle(scene);
        await _click(scene, _dialogButton(scene).getGlobalRect().getCenter());
        await _until(() => cubit.state.active != null && !cubit.state.pending);
        // Save the sibling first through the Resource Library; it must never deploy.
        await _select(scene, _secondPosition);
        await _choose(scene, Workspace3D.catalog, ResourceKind.cloudStorage);
        _fillJson(scene, _document('blacksmith-native-save-only'));
        await _settle(scene);
        await _click(scene,
            _configurationButton(scene, 'Save').getGlobalRect().getCenter());
        await _until(() =>
            cubit.state.configurationDraft == null && !cubit.state.pending);
        _check(grid.state.resources[_secondPosition]!.deployment == null,
            'Save-only has no deployment.');
        await _select(scene);
        await _choose(scene, Workspace3D.catalog, ResourceKind.cloudStorage);
        tree.getRoot()!
          ..setSize(Vector2i.fromXY(960, 640))
          ..setContentScaleSize(Vector2i.fromXY(960, 640));
        await _settle(scene);
        _fillJson(scene, _document('blacksmith-native-deploy-retry'));
        await _settle(scene);
        final deploy = _configurationButton(scene, 'Deploy');
        _check(deploy.isDisabled(), 'Consent is initially required.');
        final consent =
            scene.getNodeT<CheckButton>('$_configurationPath/Consent')!;
        await _click(scene, consent.getGlobalRect().getCenter());
        _check(!deploy.isDisabled(), 'Consent enables the explicit command.');
        // Editing must invalidate even previously approved consent.
        _fillJson(scene, '${_document('blacksmith-native-deploy-retry')} ');
        await _settle(scene);
        _check(deploy.isDisabled(), 'Changing JSON revokes approval.');
        await _click(scene, consent.getGlobalRect().getCenter());
        await _capture(scene, 'deployment_review_960.png');
        await _click(scene, deploy.getGlobalRect().getCenter());
        await _until(() =>
            !cubit.state.pending &&
            grid.state.resources[_position]?.deployment?.status == 'failed');
        _check(
            grid.state.resources[_position]!.configuration != null &&
                deploy.isDisabled(),
            'Provider rejection retains saved cube/configuration; retry requires new consent.');
        _cube(scene);
        await _capture(scene, 'deployment_failed.png');
        await _click(scene, consent.getGlobalRect().getCenter());
        _client.loseDeploymentResponse = true;
        await _click(scene, deploy.getGlobalRect().getCenter());
        await _until(() =>
            !cubit.state.pending && cubit.state.configurationDraft!.uncertain);
        _check((await _stats())['creates'] == 2,
            'Only the explicitly approved retry follows rejection; response loss never retries automatically.');
        await _capture(scene, 'deployment_unknown.png');
        await _click(scene,
            _configurationButton(scene, 'Save').getGlobalRect().getCenter());
        await _until(() =>
            !cubit.state.pending &&
            !cubit.state.configurationDraft!.uncertain &&
            grid.state.resources[_position]?.deployment?.status == 'unknown');
        _check(
            (await _stats())['creates'] == 2 &&
                (await _stats())['inspections'] == 0,
            'Check Save confirms the database commit without contacting the provider.');
        await _click(scene, deploy.getGlobalRect().getCenter());
        await _until(() =>
            !cubit.state.pending &&
            grid.state.resources[_position]?.deployment?.status == 'succeeded');
        final deployed = grid.state.resources[_position]!;
        _check(
            deployed.configuration != null &&
                grid.state.resources[_secondPosition]!.deployment == null,
            'Deployment retains both separate configurations.');
        final stats = await _stats();
        _check(
            stats['creates'] == 2 &&
                stats['buckets'] == 1 &&
                stats['attempts'] == 3 &&
                stats['inspections'] == 1 &&
                stats['resources'] == 2 &&
                stats['configurations'] == 2 &&
                stats['operations'] == 1,
            'SQL counts and provider call counts confirm the bounded operation.');
        await _capture(scene, 'deployment_verified_dialog.png');
        await _click(scene,
            _configurationButton(scene, 'Cancel').getGlobalRect().getCenter());
        checkEditorFraming(scene);
        _cube(scene);
        _cube(scene, _secondPosition);
        await _capture(scene, 'deployment_workspace_960.png');
        await File('$_output/journey.json').writeAsString(jsonEncode({
          'save_pid': pid,
          'design_id': cubit.state.active!.id,
          'resource_id': deployed.id,
          'operation_id': deployed.deployment!.id,
          'revision': deployed.revision,
          'resources': _snapshot(grid),
          'fake_provider': true,
          'stats': stats
        }));
      } else {
        final saved =
            jsonDecode(await File('$_output/journey.json').readAsString())
                as Map<String, dynamic>;
        _check(saved['save_pid'] != pid,
            'Quit and restart must use distinct OS processes.');
        await _open(scene, cubit, saved['design_id'] as String);
        final deployed = grid.state.resources[_position]!;
        _check(
            deployed.id == saved['resource_id'] &&
                deployed.revision == saved['revision'] &&
                deployed.deployment!.id == saved['operation_id'] &&
                deployed.deployment!.status == 'succeeded',
            'Same identity, configuration and durable outcome restored.');
        _check(grid.state.resources[_secondPosition]!.deployment == null,
            'Saved sibling remains undeployed.');
        _check(
            const DeepCollectionEquality()
                .equals(_snapshot(grid), saved['resources']),
            'Both Resource IDs, tiles, complete configurations, revisions and deployment records survive restart.');
        _check(cubit.state.persistenceMessage.contains('succeeded'),
            'The existing workspace summary displays the persisted outcome.');
        final summary =
            scene.getNodeT<Label>('${Workspace3D.header}/Rows/ActiveDesign')!;
        _check(
            !scene
                    .getNodeT<Control>(Workspace3D.inspector)!
                    .isVisibleInTree() &&
                summary.isVisibleInTree() &&
                summary.getTooltipText().contains('succeeded'),
            'Deployment feedback stays retrievable in the header with Inspector closed.');
        _cube(scene);
        _cube(scene, _secondPosition);
        checkEditorFraming(scene);
        await _capture(scene, 'deployment_reopened_workspace.png');
        await _select(scene);
        await openWorkspaceAction(scene, Workspace3D.inspectorToggle);
        _check(
            scene
                    .getNodeT<Label>('${Workspace3D.details}/Deployment')!
                    .getText()
                    .contains('succeeded') &&
                scene
                    .getNodeT<Label>('${Workspace3D.details}/Identity')!
                    .getTooltipText()
                    .contains(deployed.id!),
            'Docked Inspector displays restored server evidence without an extra request.');
        await _click(
            scene,
            scene
                .getNodeT<Button>('${Workspace3D.details}/Configure')!
                .getGlobalRect()
                .getCenter());
        _check(
            scene
                    .getNodeT<Button>(
                        '${Workspace3D.inspector}/Content/Heading/Close')!
                    .isDisabled() &&
                scene
                    .getNodeT<Button>(Workspace3D.inspectorToggle)!
                    .isDisabled(),
            'Modal configuration also blocks keyboard actions on the underlying dock.');
        _check(
            const DeepCollectionEquality()
                    .equals(jsonDecode(_json(scene).getText()), {
                  'schemaVersion': grid
                      .state.resources[_position]!.configuration!.schemaVersion,
                  'configuration':
                      grid.state.resources[_position]!.configuration!.values
                }) &&
                !scene
                    .getNodeT<CheckButton>('$_configurationPath/Consent')!
                    .isPressed(),
            'Reopened configuration is editable, canonical and never pre-consented.');
        await _capture(scene, 'deployment_restored.png');
        await _click(scene,
            _configurationButton(scene, 'Cancel').getGlobalRect().getCenter());
        // A second Open in this same process must also be read-only and idempotent.
        await _open(scene, cubit, saved['design_id'] as String);
        _check(
            const DeepCollectionEquality()
                .equals(_snapshot(grid), saved['resources']),
            'Repeated Open retains the complete same snapshot.');
        _check(_client.events.every((e) => e['method'] == 'GET'),
            'Restart/Open performs only metadata reads.');
        final after = await _stats();
        _check(const DeepCollectionEquality().equals(after, initial),
            'Open, configuration review and repeated Open change no SQL counts or provider counters.');
        await File('$_output/reopened.json').writeAsString(jsonEncode(
            {...saved, 'open_pid': pid, 'restored': true, 'stats': after}));
      }
      await File('$_output/$_phase-http.json')
          .writeAsString(jsonEncode(_client.events));
      GD.print(Variant(
          'BLACKSMITH_PERSISTENCE_${_phase.toUpperCase()}_PASSED real_api=true provider=fake pid=$pid'));
      tree.getRoot()!.emitSignal('tree_exiting');
      await _until(() => cubit.isClosed && grid.isClosed);
      tree.quit();
    } catch (error, stack) {
      GD.print(Variant('BLACKSMITH_DEPLOYMENT_FAILED: $error\n$stack'));
      tree.quit(exitCode: 1);
    }
  });
}

List<Map<String, Object?>> _snapshot(IsomapGridBloc grid) {
  final entries = grid.state.resources.entries.toList()
    ..sort((a, b) => a.key.row == b.key.row
        ? a.key.col.compareTo(b.key.col)
        : a.key.row.compareTo(b.key.row));
  return entries.map((entry) {
    final resource = entry.value;
    final deployment = resource.deployment;
    return <String, Object?>{
      'id': resource.id,
      'designId': resource.designId,
      'row': entry.key.row,
      'col': entry.key.col,
      'revision': resource.revision,
      'etag': resource.etag,
      'configurationState': resource.configurationState,
      'configuration': resource.configuration!.values,
      'schemaVersion': resource.configuration!.schemaVersion,
      'deployment': deployment == null
          ? null
          : {
              'id': deployment.id,
              'resourceId': deployment.resourceId,
              'designId': deployment.designId,
              'resourceRevision': deployment.resourceRevision,
              'projectId': deployment.projectId,
              'bucketName': deployment.bucketName,
              'location': deployment.location,
              'status': deployment.status,
              'code': deployment.code,
              'ownershipVerified': deployment.ownershipVerified,
            },
    };
  }).toList();
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
  await dismissWorkspaceMenus(scene);
  final p = const GridLayout3D().worldPosition(position);
  await _click(
      scene,
      Workspace3D.project(
          scene, (scene as Node3D).toGlobal(Vector3(x: p.x, y: .12, z: p.z))));
}

Future<void> _choose(Node scene, String group, ResourceKind kind) async {
  if (group == Workspace3D.catalog &&
      !scene.getNodeT<Control>(Workspace3D.sidebar)!.isVisibleInTree()) {
    await openWorkspaceAction(scene, Workspace3D.libraryToggle);
  }
  await _click(
      scene,
      scene
          .getNodeT<Button>('$group/${resourceVisuals3D[kind]!.buttonName}')!
          .getGlobalRect()
          .getCenter());
}

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

const _configurationPath = 'DesignLayer/ConfigurationControls/Shade/Dialog';
TextEdit _json(Node scene) =>
    scene.getNodeT<TextEdit>('$_configurationPath/Json')!;
Button _configurationButton(Node scene, String name) =>
    scene.getNodeT<Button>('$_configurationPath/$name')!;
void _fillJson(Node scene, String text) {
  _json(scene)
    ..setText(text)
    ..textChanged.emit();
}

String _document(String bucket) => di
    .sl<ResourceRepository>()
    .configurationText(ResourceConfiguration(schemaVersion: 1, values: {
      'projectId': 'example-project-123',
      'bucketName': bucket,
      'location': 'europe-west9'
    }));

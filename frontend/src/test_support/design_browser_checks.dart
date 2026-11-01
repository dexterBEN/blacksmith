// Real repository/Cubit/browser integration with controlled HTTP metadata.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:async' as async;
import 'dart:convert';
import 'dart:io';
import 'package:godot_dart/godot_dart.dart';
import 'package:http/http.dart' as http;
import '../lib/core/di/service_locator.dart' as di;
import '../lib/data/repositories/design_repository.dart';
import '../lib/data/repositories/resource_repository.dart';
import '../lib/data/repositories/cloud_storage_repository.dart';
import '../lib/data/services/cloud_services_api.dart';
import '../lib/domain/bloc/design/design_cubit.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import '../lib/domain/bloc/isomap_grid/isomap_grid_event.dart';
import '../lib/domain/models/design_browser_state.dart';
import '../lib/domain/models/grid_position.dart';
import '../lib/domain/models/persisted_resource.dart';
import '../lib/prototypes/isometric_3d/design_browser_3d.dart';
import '../lib/prototypes/isometric_3d/grid_layout.dart';
import '../lib/prototypes/isometric_3d/workspace_3d.dart';
import 'workspace_test_input.dart';
import 'isometric_3d_framing_checks.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _c = '33333333-3333-4333-8333-333333333333';

class _Metadata extends http.BaseClient {
  String mode = 'pending';
  bool failOpen = false;
  int lists = 0, gets = 0, writes = 0;
  final pending = async.Completer<http.StreamedResponse>();
  static List<Map<String, Object?>> get records => [
        {
          'id': _b,
          'name': 'Development workspace',
          'updatedAtUtc': '2026-10-29T10:00:00Z'
        },
        {
          'id': _a,
          'name': 'Production infrastructure',
          'updatedAtUtc': '2026-10-31T10:00:00Z'
        },
        {'id': _c, 'name': null, 'updatedAtUtc': null}
      ];
  static http.StreamedResponse response(Object body, [int status = 200]) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          headers: {'content-type': 'application/json; charset=utf-8'});
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET') {
      writes++;
      throw StateError('Metadata writes forbidden.');
    }
    if (request.url.path == '/designs') {
      lists++;
      if (mode == 'pending') return pending.future;
      if (mode == 'error') return response({'SECRET': 'server detail'}, 503);
      if (mode == 'empty') return response([]);
      if (mode == 'many') {
        return response(List.generate(
            125,
            (i) => {
                  'id':
                      '44444444-4444-4444-8444-${i.toString().padLeft(12, '0')}',
                  'name': 'Project ${i.toString().padLeft(3, '0')}',
                  'updatedAtUtc': '2026-10-31T10:00:00Z'
                }));
      }
      return response(records);
    }
    gets++;
    if (failOpen) return response({'SECRET': 'open detail'}, 503);
    final id = request.url.path.split('/').last;
    final row = records.firstWhere((r) => r['id'] == id);
    return response(row);
  }
}

class _NoHttp extends http.BaseClient {
  int requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    throw StateError('Unexpected resource/cloud HTTP.');
  }
}

class _Resources extends ResourceRepository {
  _Resources() : super(baseUrl: 'http://forbidden.invalid', client: _noHttp);
  int reads = 0;
  bool hold = true;
  final pending = async.Completer<List<PersistedResource>>();
  static List<PersistedResource> records(String id) => [
        PersistedResource(
            id: '55555555-5555-4555-8555-555555555555',
            designId: id,
            position: const GridPos(1, 1)),
        if (id == _a)
          PersistedResource(
              id: '66666666-6666-4666-8666-666666666666',
              designId: id,
              position: const GridPos(4, 3))
      ];
  @override
  Future<List<PersistedResource>> listForDesign(String id,
      {int rows = 6, int cols = 6}) {
    reads++;
    return hold ? pending.future : async.Future.value(records(id));
  }
}

class _Grid extends IsomapGridBloc {
  int selections = 0, placements = 0;
  @override
  void onEvent(IsomapGridEvent event) {
    if (event is TileClicked) selections++;
    if (event is PlaceResource) placements++;
    super.onEvent(event);
  }
}

final _metadata = _Metadata(), _noHttp = _NoHttp();
late final _Resources _resources;
late final _Grid _grid;
void beforeStartup() {
  if (Engine.singleton.isEditorHint()) return;
  _resources = _Resources();
  _grid = _Grid();
  final api =
      CloudServicesApi(baseUrl: 'http://forbidden.invalid', client: _noHttp);
  di.sl.registerSingleton<CloudServicesApi>(api, dispose: (a) => a.close());
  di.sl.registerSingleton<CloudStorageRepository>(
      CloudStorageRepository(api, projectId: 'fixture-only'));
  di.sl.registerSingleton<DesignRepository>(
      DesignRepository(baseUrl: 'http://metadata.invalid', client: _metadata),
      dispose: (r) => r.close());
  di.sl.registerSingleton<ResourceRepository>(_resources,
      dispose: (r) => r.close());
  di.sl.registerSingleton<IsomapGridBloc>(_grid, dispose: (g) => g.close());
}

void afterStartup() {
  if (Engine.singleton.isEditorHint()) return;
  async.Timer.run(() async {
    final tree = Engine.singleton.getMainLoop()! as SceneTree;
    try {
      final window = tree.getRoot()!;
      window
        ..setFlag(WindowFlags.flagMousePassthrough, true)
        ..setFlag(WindowFlags.flagNoFocus, true)
        ..setContentScaleMode(WindowContentScaleMode.disabled)
        ..setContentScaleSize(Vector2i.fromXY(0, 0));
      await _until(() => tree.getCurrentScene() != null);
      final scene = tree.getCurrentScene()!;
      final cubit = di.sl<DesignCubit>();
      scene.getViewport()!
        ..setDisableInput(false)
        ..call('notify_mouse_entered');
      Control c(String path) => scene.getNodeT<Control>(path)!;
      Button b(String path) => scene.getNodeT<Button>(path)!;
      Future<void> click(String path) =>
          workspaceClick(scene, c(path).getGlobalRect().getCenter());
      const open = '${Workspace3D.header}/Rows/Actions/OpenDesign';
      const create = '${Workspace3D.header}/Rows/Actions/NewDesign';
      Future<void> snap(String name) async {
        await RenderingServer.singleton.framePostDraw.asFuture(scene);
        await RenderingServer.singleton.framePostDraw.asFuture(scene);
        final output = Platform.environment['BLACKSMITH_WORKSPACE_OUTPUT']!;
        _check(
            scene
                    .getViewport()!
                    .getTexture()!
                    .getImage()!
                    .savePng('$output/$name.png') ==
                GDError.ok,
            'Actual native capture.');
      }

      void search(String text) {
        final input = scene.getNodeT<LineEdit>(DesignBrowser3D.search)!;
        input
          ..setText(text)
          ..textChanged.emit(text);
      }

      Future<void> ready() =>
          _until(() => cubit.state.browser.status == DesignListStatus.ready);
      final original = _grid.state;
      await click(open);
      _check(
          cubit.state.browser.status == DesignListStatus.loading &&
              b(DesignBrowser3D.confirm).isDisabled() &&
              _resources.reads == 0,
          'Open requests only lightweight metadata and initially has no selection.');
      await snap('browser_loading');
      await click(DesignBrowser3D.close);
      _check(!cubit.state.dialogOpen && _grid.state == original,
          'Loading list can be canceled without touching the workspace.');
      _metadata.mode = 'normal';
      await click(open);
      await ready();
      _metadata.pending.complete(_Metadata.response([]));
      await _pause();
      _check(cubit.state.browser.entries.length == 3,
          'Late canceled metadata cannot replace the current catalog.');
      for (final size in [(1600, 900), (1152, 648), (960, 640)]) {
        window.setSize(Vector2i.fromXY(size.$1, size.$2));
        await _until(() =>
            scene.getViewport()!.getVisibleRect().size.x == size.$1 &&
            scene.getViewport()!.getVisibleRect().size.y == size.$2);
        await _pause();
        final bounds = c(DesignBrowser3D.dialog).getGlobalRect();
        _check(
            (bounds.getCenter() -
                            scene.getViewport()!.getVisibleRect().getCenter())
                        .length <
                    1 &&
                bounds.position.y >= 16 &&
                bounds.end.y <= size.$2 - 16,
            'Browser is centered and fits actual desktop window sizes.');
        _check(!c('DesignLayer/DesignControls/Shade').isVisibleInTree(),
            'The old manual ID dialog is absent from the Open workflow.');
        _check(
            scene
                    .getNodeT<Label>(
                        '${DesignBrowser3D.rows}/Row_0/Margin/Content/Labels/Name')!
                    .getText() ==
                'Production infrastructure',
            'Real decoded metadata sorts by most recent update.');
        _check(c(DesignBrowser3D.confirm).getGlobalRect().end.y <= bounds.end.y,
            'Footer remains accessible.');
        final events = _grid.selections;
        await click(create);
        await workspaceClick(scene, Vector2(x: 8, y: size.$2 - 8));
        _check(
            cubit.state.mode == DesignDialogMode.open &&
                _grid.selections == events &&
                _grid.state == original,
            'Modal backdrop and toolbar clicks never reach the workspace.');
        for (var i = 0; i < 10; i++) {
          for (final pressed in [true, false]) {
            scene.getViewport()!.pushInput(
                InputEventKey()
                  ..setKeycode(Key.tab)
                  ..setPressed(pressed),
                inLocalCoords: true);
          }
          await _pause();
          final focus = scene.getViewport()!.guiGetFocusOwner();
          _check(focus != null && c(DesignBrowser3D.dialog).isAncestorOf(focus),
              'Tab focus stays in the browser.');
        }
        await snap('browser_${size.$1}');
      }
      search('dEVELop');
      await _pause();
      _check(c(DesignBrowser3D.rows).getChildCount() == 1,
          'Search filters visible Designs by name without another HTTP request.');
      await click('${DesignBrowser3D.rows}/Row_0');
      await click('${DesignBrowser3D.rows}/Row_0');
      _check(
          cubit.state.openId == _b &&
              b('${DesignBrowser3D.rows}/Row_0').isPressed() &&
              !b(DesignBrowser3D.confirm).isDisabled() &&
              _metadata.gets == 0,
          'A row selects only; clicking it again retains the highlight.');
      search('No matching name');
      await _pause();
      _check(
          c(DesignBrowser3D.rows).getChildCount() == 0 &&
              b(DesignBrowser3D.confirm).isDisabled(),
          'Changing the filter clears an invisible selection.');
      await snap('browser_no_match');
      await dismissWorkspaceMenus(scene);
      _check(!cubit.state.dialogOpen && b(open).hasFocus(),
          'Escape cancels and restores toolbar focus.');
      _metadata.mode = 'error';
      await click(open);
      await _until(
          () => cubit.state.browser.status == DesignListStatus.failure);
      _check(
          b(DesignBrowser3D.retry).isVisibleInTree() &&
              !cubit.state.browser.error!.contains('SECRET'),
          'List error is sanitized and has Retry.');
      await snap('browser_error');
      _metadata.mode = 'empty';
      await click(DesignBrowser3D.retry);
      await ready();
      _check(
          cubit.state.browser.entries.isEmpty &&
              b(DesignBrowser3D.newDesign).isVisibleInTree(),
          'Empty results offer the existing New Design flow.');
      await snap('browser_empty');
      await click(DesignBrowser3D.newDesign);
      _check(
          cubit.state.mode == DesignDialogMode.create &&
              c('DesignLayer/DesignControls/Shade').isVisibleInTree(),
          'Empty-list New Design reuses the existing creation form.');
      await click('DesignLayer/DesignControls/Shade/Dialog/Cancel');
      _metadata.mode = 'normal';
      await click(open);
      await ready();
      await selectDesignInBrowser(scene, cubit, _a);
      await click(DesignBrowser3D.confirm);
      await _until(() => _resources.reads == 1);
      _check(
          cubit.state.pending &&
              cubit.state.active == null &&
              !scene.getNodeT<Node3D>('GridRoot')!.isVisibleInTree() &&
              b(DesignBrowser3D.cancel).isDisabled() &&
              b(DesignBrowser3D.close).isDisabled(),
          'Opening waits for the complete canonical resource load and prevents duplicate submissions.');
      await click(DesignBrowser3D.confirm);
      await cubit.submit();
      _check(_metadata.gets == 1,
          'Duplicate opening never repeats the selected-Design request.');
      await snap('browser_opening');
      _resources.pending.complete(_Resources.records(_a));
      await _until(
          () => cubit.state.active?.id == _a && !cubit.state.dialogOpen);
      await _pause();
      checkEditorFraming(scene);
      _check(scene.getNodeT<Node3D>('ResourceRoot')!.getChildCount() == 2,
          'Only successful load reveals restored resources.');
      window.setSize(Vector2i.fromXY(1600, 900));
      await _until(() => scene.getViewport()!.getVisibleRect().size.x == 1600);
      await _pause();
      final p = const GridLayout3D().worldPosition(const GridPos(3, 3));
      await workspaceClick(
          scene,
          Workspace3D.project(scene,
              (scene as Node3D).toGlobal(Vector3(x: p.x, y: .12, z: p.z))));
      await openWorkspaceAction(scene, Workspace3D.libraryToggle);
      await click('${Workspace3D.catalog}/ComputeEngine');
      await confirmResourceChoice(scene);
      final before = cubit.state.active;
      final snapshot = _grid.state;
      await click(open);
      await ready();
      await selectDesignInBrowser(scene, cubit, _b);
      _check(
          cubit.state.requiresDiscard &&
              b(DesignBrowser3D.confirm).isDisabled(),
          'Unsaved changes require approval before replacing an active Design.');
      await click(DesignBrowser3D.discard);
      _metadata.failOpen = true;
      await click(DesignBrowser3D.confirm);
      await _until(() => cubit.state.status == DesignStatus.failure);
      _check(
          cubit.state.dialogOpen &&
              cubit.state.active == before &&
              _grid.state == snapshot &&
              !cubit.state.error!.contains('SECRET'),
          'Failed opening preserves current Design, resources and selection.');
      await snap('browser_open_failed');
      _metadata.failOpen = false;
      _resources.hold = false;
      await click(DesignBrowser3D.confirm);
      await _until(
          () => cubit.state.active?.id == _b && !cubit.state.dialogOpen);
      _check(_grid.state.resources.length == 1 && _grid.state.selected == null,
          'Retry opens the selected Design through the existing atomic hydration path.');
      _metadata.mode = 'many';
      await click(open);
      await ready();
      _check(
          cubit.state.browser.entries.length == 125 &&
              c(DesignBrowser3D.rows).getChildCount() == 50,
          'Large catalogs render at most fifty rows per client-side page.');
      await click(DesignBrowser3D.next);
      await click(DesignBrowser3D.next);
      _check(
          cubit.state.browser.page == 2 &&
              c(DesignBrowser3D.rows).getChildCount() == 25,
          'Last page is bounded and retains all results.');
      search('Project 124');
      await _pause();
      _check(
          cubit.state.browser.page == 0 &&
              c(DesignBrowser3D.rows).getChildCount() == 1,
          'Search spans the entire catalog and resets pagination.');
      search('');
      await _pause();
      b('${DesignBrowser3D.rows}/Row_49').grabFocus();
      await _pause();
      final last = c('${DesignBrowser3D.rows}/Row_49').getGlobalRect();
      final scroll = c('${DesignBrowser3D.content}/Scroll').getGlobalRect();
      _check(last.end.y <= scroll.end.y + 1, 'Scrolling follows focused rows.');
      await snap('browser_paged');
      await click(DesignBrowser3D.cancel);
      _check(
          cubit.state.active?.id == _b &&
              _resources.reads == 2 &&
              _metadata.writes == 0 &&
              _noHttp.requests == 0,
          'Browsing/selection never preloads resource payloads, writes metadata or provisions cloud services.');
      GD.print(Variant(
          'BLACKSMITH_ISSUE81_BROWSER_PASSED sizes=3 loading=true search=true '
          'selection=true dates=true empty=true retry=true atomic_open=true failure_preserves=true '
          'discard=true paging=125 focus=true backdrop=true stale_response=true http_writes=0 cloud_requests=0'));
      window.treeExiting.emit();
      await _until(() => cubit.isClosed && _grid.isClosed);
      tree.quit();
    } catch (error, stack) {
      GD.print(Variant('BLACKSMITH_ISSUE81_BROWSER_FAILED $error\n$stack'));
      tree.quit(exitCode: 1);
    }
  });
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _pause() =>
    Future<void>.delayed(const Duration(milliseconds: 200));
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 150; i++) {
    if (condition()) return;
    await _pause();
  }
  throw StateError('Timed out waiting for the Design browser.');
}

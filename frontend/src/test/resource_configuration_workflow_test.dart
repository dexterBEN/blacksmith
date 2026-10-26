import 'dart:async';
import 'package:test/test.dart';
import 'package:blacksmith_front/data/repositories/resource_repository.dart';
import 'package:blacksmith_front/domain/bloc/design/design_cubit.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_event.dart';
import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'package:blacksmith_front/domain/models/placed_resource.dart';
import 'package:blacksmith_front/domain/models/persisted_resource.dart';
import 'package:blacksmith_front/domain/models/resource_configuration.dart';
import 'package:blacksmith_front/domain/models/resource_kind.dart';
import 'design_persistence_test.dart' as fixtures;

class ConfiguredResources extends fixtures.Resources {
  int rejectStatus = 400;
  bool rejectConfigured = false,
      loseConfigured = false,
      unknownUncommitted = false,
      failAfterWrite = false;
  final writtenIds = <String>[];
  @override
  Future<PersistedResource> getById(String designId, String id,
      {int rows = 6, int cols = 6}) async {
    if (failRead) throw const ResourceFailure('Read failed.');
    final found = records.where((r) => r.id == id).toList();
    if (found.isEmpty) {
      throw const ResourceFailure('Resource not found.', status: 404);
    }
    return found.single;
  }

  @override
  Future<PersistedResource> writeConfigured(
      String designId, GridPos position, PlacedResource intent,
      {int rows = 6, int cols = 6}) async {
    writtenIds.add(intent.id ?? intent.localKey);
    if (rejectConfigured || unknownUncommitted) {
      puts++;
      throw ResourceFailure(
          rejectConfigured
              ? 'location rejected by backend.'
              : 'Outcome unknown.',
          ambiguous: unknownUncommitted,
          status: rejectConfigured ? rejectStatus : null);
    }
    final existing = records.where((r) => r.id == intent.id).toList();
    if (existing.isNotEmpty &&
        existing.single.configuration == intent.configuration) {
      puts++;
      return existing.single;
    }
    final result = await super
        .writeConfigured(designId, position, intent, rows: rows, cols: cols);
    if (failAfterWrite) failRead = true;
    if (loseConfigured) {
      throw const ResourceFailure('Response lost.', ambiguous: true);
    }
    return result;
  }
}

void main() {
  late fixtures.Designs designs;
  late ConfiguredResources resources;
  late IsomapGridBloc grid;
  late DesignCubit cubit;
  const pos = fixtures.pos, other = GridPos(4, 1);
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 10));
  Future<void> create() async {
    cubit.open();
    cubit.changeName('Configured resources');
    await cubit.submit();
    grid.add(const TileClicked(pos));
    await settle();
  }

  void fill([String bucket = 'configured-bucket']) {
    cubit.changeResourceConfigurationText(resources
        .configurationText(ResourceConfiguration(schemaVersion: 1, values: {
      'projectId': 'example-project-123',
      'bucketName': bucket,
      'location': 'europe-west9'
    })));
  }

  setUp(() {
    designs = fixtures.Designs();
    resources = ConfiguredResources();
    grid = IsomapGridBloc();
    cubit = DesignCubit(designs, grid, resources: resources);
  });
  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
    await grid.close();
    designs.close();
    resources.close();
  });

  test('requires active Design and tile; Cancel has no side effects', () async {
    grid.add(const TileClicked(pos));
    await settle();
    cubit.openResourceConfiguration();
    expect(cubit.state.configurationDraft, isNull);
    await create();
    cubit.openResourceConfiguration();
    expect(cubit.state.configurationDraft, isNotNull);
    expect(grid.state.resources, isEmpty);
    expect(cubit.state.canSave, isFalse);
    cubit.cancelResourceConfiguration();
    expect(grid.state.resources, isEmpty);
    expect(resources.puts, 0);
    expect(resources.posts, 0);
  });
  test('invalid JSON preserves form and sends no HTTP write', () async {
    await create();
    cubit.openResourceConfiguration();
    final key = cubit.state.configurationDraft!.resource.localKey;
    cubit.changeResourceConfigurationText('{broken');
    await cubit.saveResourceConfiguration();
    expect(cubit.state.configurationDraft!.text, '{broken');
    expect(cubit.state.configurationDraft!.error, contains('syntax'));
    expect(cubit.state.configurationDraft!.resource.localKey, key);
    expect(resources.puts, 0);
    expect(grid.state.resources, isEmpty);
  });
  test(
      'captures target, blocks double submit/New/Open, publishes only after confirmation',
      () async {
    await create();
    cubit.openResourceConfiguration();
    fill();
    final key = cubit.state.configurationDraft!.resource.localKey;
    resources.pending = Completer<void>();
    final saving = cubit.saveResourceConfiguration();
    await settle();
    expect(grid.state.resources, isEmpty);
    expect(cubit.state.pending, isTrue);
    await cubit.saveResourceConfiguration();
    cubit.open();
    cubit.openExisting();
    cubit.cancelResourceConfiguration();
    cubit.changeResourceConfigurationText('{}');
    grid.add(const TileClicked(other));
    await settle();
    expect(cubit.state.configurationDraft!.resource.localKey, key);
    expect(resources.puts, 1);
    resources.pending!.complete();
    await saving;
    expect(grid.state.resources.keys, [pos]);
    expect(grid.state.selected, other);
    expect(grid.state.resources[pos]!.id, key);
    expect(resources.posts, 0);
    expect(cubit.state.configurationDraft, isNull);
    expect(cubit.state.saved, isTrue);
    await cubit.save();
    expect(resources.puts, 1);
    expect(resources.posts, 0);
  });
  test('rejected write retains exact text and UUID for explicit retry',
      () async {
    await create();
    cubit.openResourceConfiguration();
    fill();
    final draft = cubit.state.configurationDraft!;
    resources.rejectConfigured = true;
    await cubit.saveResourceConfiguration();
    expect(grid.state.resources, isEmpty);
    expect(cubit.state.configurationDraft!.text, draft.text);
    expect(cubit.state.configurationDraft!.uncertain, isFalse);
    resources.rejectConfigured = false;
    await cubit.saveResourceConfiguration();
    expect(resources.writtenIds,
        [draft.resource.localKey, draft.resource.localKey]);
    expect(resources.records.length, 1);
  });
  test('lost committed response reconciles original ID with reads only',
      () async {
    await create();
    cubit.openResourceConfiguration();
    fill();
    final key = cubit.state.configurationDraft!.resource.localKey;
    resources.loseConfigured = true;
    await cubit.saveResourceConfiguration();
    expect(cubit.state.configurationDraft!.uncertain, isTrue);
    expect(grid.state.resources, isEmpty);
    expect(resources.records.single.id, key);
    cubit.changeResourceConfigurationText('{}');
    await cubit.saveResourceConfiguration();
    expect(resources.puts, 1);
    expect(grid.state.resources[pos]!.id, key);
    expect(cubit.state.saved, isTrue);
  });
  test('closing unknown form retains header recovery guard and original intent',
      () async {
    await create();
    cubit.openResourceConfiguration();
    fill();
    resources.loseConfigured = true;
    await cubit.saveResourceConfiguration();
    final key = cubit.state.configurationDraft!.resource.localKey;
    cubit.cancelResourceConfiguration();
    cubit.openResourceConfiguration();
    expect(cubit.state.configurationDraft, isNull);
    expect(cubit.state.saveUncertain, isTrue);
    await cubit.save();
    expect(grid.state.resources[pos]!.id, key);
    expect(resources.puts, 1);
  });
  test('timeout without observed row stays unknown and never resubmits',
      () async {
    await create();
    cubit.openResourceConfiguration();
    fill();
    resources.unknownUncommitted = true;
    await cubit.saveResourceConfiguration();
    await cubit.saveResourceConfiguration();
    await cubit.saveResourceConfiguration();
    expect(resources.puts, 1);
    expect(cubit.state.configurationDraft!.uncertain, isTrue);
    expect(grid.state.resources, isEmpty);
  });
  test(
      'successful write followed by failed read-back remains hidden and recoverable',
      () async {
    await create();
    cubit.openResourceConfiguration();
    fill();
    resources.failAfterWrite = true;
    await cubit.saveResourceConfiguration();
    expect(grid.state.resources, isEmpty);
    expect(cubit.state.configurationDraft!.uncertain, isTrue);
    resources.failRead = false;
    await cubit.saveResourceConfiguration();
    expect(resources.puts, 1);
    expect(grid.state.resources.length, 1);
  });
  test(
      'two configured resources persist; editing/no-op retains ID, tile and current revision',
      () async {
    await create();
    cubit.openResourceConfiguration();
    fill('bucket-first');
    await cubit.saveResourceConfiguration();
    final first = grid.state.resources[pos]!;
    grid.add(const TileClicked(other));
    await settle();
    cubit.openResourceConfiguration();
    fill('bucket-second');
    await cubit.saveResourceConfiguration();
    expect(resources.records.length, 2);
    expect(cubit.state.saved, isTrue);
    grid.add(const TileClicked(pos));
    await settle();
    cubit.openResourceConfiguration();
    fill('bucket-first-edited');
    await cubit.saveResourceConfiguration();
    final edited = grid.state.resources[pos]!;
    expect(edited.id, first.id);
    expect(edited.revision, 2);
    expect(resources.records.length, 2);
    cubit.openResourceConfiguration();
    await cubit.saveResourceConfiguration();
    expect(grid.state.resources[pos]!.revision, 2);
    expect(resources.posts, 0);
    await cubit.save();
    expect(resources.puts, 4);
    expect(resources.records.length, 2);
  });
  test(
      'legacy unconfigured resource requires explicit identifiers and keeps its original ID',
      () async {
    resources.records = [
      const PersistedResource(
          id: fixtures.rid,
          designId: fixtures.id,
          position: pos,
          etag: '"resource-22345678123412341234123456789abc-r1"')
    ];
    cubit.openExisting();
    cubit.changeOpenId(fixtures.id);
    await cubit.submit();
    grid.add(const TileClicked(pos));
    await settle();
    cubit.openResourceConfiguration();
    expect(cubit.state.configurationDraft!.text, contains('"projectId": ""'));
    await cubit.saveResourceConfiguration();
    expect(resources.puts, 0);
    expect(grid.state.resources[pos]!.configuration, isNull);
    fill();
    await cubit.saveResourceConfiguration();
    expect(resources.records.single.id, fixtures.rid);
    expect(grid.state.resources[pos]!.revision, 2);
  });
  test(
      'concurrent backend change is rejected without erasing the form or local cube',
      () async {
    await create();
    cubit.openResourceConfiguration();
    fill();
    await cubit.saveResourceConfiguration();
    final before = grid.state.resources[pos]!;
    cubit.openResourceConfiguration();
    fill('desired-edit');
    resources.records = []; // External deletion; no implicit recreate.
    await cubit.saveResourceConfiguration();
    expect(grid.state.resources[pos], before);
    expect(resources.puts, 1);
    expect(cubit.state.configurationDraft!.text, contains('desired-edit'));
    expect(cubit.state.configurationDraft!.error,
        contains('backend Design changed'));
  });
  test('revision rejection preserves ID, revision, grid and edited document',
      () async {
    await create();
    cubit.openResourceConfiguration();
    fill();
    await cubit.saveResourceConfiguration();
    final before = grid.state.resources[pos]!;
    cubit.openResourceConfiguration();
    fill('desired-revision-edit');
    resources.rejectConfigured = true;
    resources.rejectStatus = 412;
    await cubit.saveResourceConfiguration();
    expect(grid.state.resources[pos], before);
    expect(cubit.state.configurationDraft!.resource.id, before.id);
    expect(cubit.state.configurationDraft!.resource.revision, before.revision);
    expect(cubit.state.configurationDraft!.text,
        contains('desired-revision-edit'));
    expect(cubit.state.configurationDraft!.uncertain, isFalse);
    expect(resources.writtenIds.last, before.id);
  });
  test(
      'cancelling an existing configuration edit preserves its entire snapshot',
      () async {
    await create();
    cubit.openResourceConfiguration();
    fill();
    await cubit.saveResourceConfiguration();
    final before = grid.state;
    cubit.openResourceConfiguration();
    fill('cancelled-edit');
    expect(cubit.state.saved, isFalse);
    cubit.cancelResourceConfiguration();
    expect(grid.state, before);
    expect(resources.puts, 1);
    expect(cubit.state.saved, isTrue);
  });
  test('tile changed during write is not overwritten by late confirmation',
      () async {
    await create();
    cubit.openResourceConfiguration();
    fill();
    resources.pending = Completer<void>();
    final saving = cubit.saveResourceConfiguration();
    await settle();
    grid.add(const PlaceResource(ResourceKind.computeEngine));
    await settle();
    resources.pending!.complete();
    await saving;
    expect(grid.state.tiles[pos], ResourceKind.computeEngine);
    expect(cubit.state.configurationDraft!.uncertain, isTrue);
    expect(resources.records.length, 1);
  });
  test(
      'a saved configuration does not mark unrelated unsaved placements as saved',
      () async {
    await create();
    grid.add(const PlaceResource(ResourceKind.cloudStorage));
    await settle();
    grid.add(const TileClicked(other));
    await settle();
    cubit.openResourceConfiguration();
    fill();
    await cubit.saveResourceConfiguration();
    expect(grid.state.resources.length, 2);
    expect(cubit.state.saved, isFalse);
    expect(grid.state.resources[pos]!.id, isNull);
    expect(resources.posts, 0);
  });
}

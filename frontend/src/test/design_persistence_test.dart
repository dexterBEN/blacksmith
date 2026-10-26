import 'dart:async';
import 'package:test/test.dart';
import 'package:blacksmith_front/data/repositories/design_repository.dart';
import 'package:blacksmith_front/data/repositories/resource_repository.dart';
import 'package:blacksmith_front/domain/bloc/design/design_cubit.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_event.dart';
import 'package:blacksmith_front/domain/models/design.dart';
import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'package:blacksmith_front/domain/models/persisted_resource.dart';
import 'package:blacksmith_front/domain/models/resource_kind.dart';
import 'package:blacksmith_front/domain/models/placed_resource.dart';
import 'package:blacksmith_front/domain/models/resource_configuration.dart';

const id = '12345678-1234-1234-1234-123456789abc';
const rid = '22345678-1234-1234-1234-123456789abc';
const pos = GridPos(2, 3);
const design = Design(id: id, name: 'Persistent smoke');
const row = PersistedResource(id: rid, designId: id, position: pos);
const catalogId = '10000000-0000-0000-0000-000000000002';

class Designs extends DesignRepository {
  Designs() : super(baseUrl: 'http://unused.test');
  bool fail = false;
  int gets = 0;
  @override
  Future<Design> create(String name) async => design;
  @override
  Future<Design> getById(String id) async {
    gets++;
    if (fail) throw const DesignFailure('Backend read failed.');
    return design;
  }
}

class Resources extends ResourceRepository {
  Resources() : super(baseUrl: 'http://unused.test');
  List<PersistedResource> records = [];
  int posts = 0, gets = 0, puts = 0;
  int rejectPostNumber = 0, unknownPostNumber = 0;
  bool staleRead = false;
  bool failRead = false,
      ambiguous = false,
      reject = false,
      loseAfterCommit = false;
  Completer<void>? pending;
  @override
  Future<List<PersistedResource>> listForDesign(String id,
      {int rows = 6, int cols = 6}) async {
    gets++;
    if (failRead) throw const ResourceFailure('Resource read failed.');
    return staleRead ? [] : List.of(records);
  }

  @override
  Future<PersistedResource> createCloudStorage(
      String designId, GridPos position,
      {int rows = 6, int cols = 6}) async {
    posts++;
    if (pending != null) await pending!.future;
    if (reject || posts == rejectPostNumber) {
      throw const ResourceFailure('Rejected.');
    }
    final unknown = ambiguous || posts == unknownPostNumber;
    final serverId = posts == 1
        ? rid
        : '32345678-1234-1234-1234-${posts.toString().padLeft(12, '0')}';
    final record = PersistedResource(
        id: serverId,
        designId: designId,
        position: position,
        catalogId: catalogId,
        etag: '"resource-${serverId.replaceAll('-', '')}-r1"');
    if (!unknown || loseAfterCommit) {
      records = [...records, record];
    }
    if (unknown) {
      throw const ResourceFailure('Unknown outcome.', ambiguous: true);
    }
    return record;
  }

  @override
  Future<PersistedResource> writeConfigured(
      String designId, GridPos position, PlacedResource intent,
      {int rows = 6, int cols = 6}) async {
    puts++;
    if (pending != null) await pending!.future;
    final serverId = intent.id ?? intent.localKey;
    final revision = (intent.revision ?? 0) + 1;
    final record = PersistedResource(
        id: serverId,
        designId: designId,
        position: position,
        name: intent.name,
        catalogId: catalogId,
        revision: revision,
        etag: '"resource-${serverId.replaceAll('-', '')}-r$revision"',
        configuration: intent.configuration,
        configurationState: 'validated');
    records = [...records.where((r) => r.id != serverId), record];
    return record;
  }
}

void main() {
  late Designs designs;
  late Resources resources;
  late IsomapGridBloc grid;
  late DesignCubit cubit;
  setUp(() {
    designs = Designs();
    resources = Resources();
    grid = IsomapGridBloc();
    cubit = DesignCubit(designs, grid, resources: resources);
  });
  tearDown(() async {
    await cubit.close();
    await grid.close();
    designs.close();
    resources.close();
  });
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 10));
  Future<void> place([ResourceKind kind = ResourceKind.cloudStorage]) async {
    grid.add(const TileClicked(pos));
    await settle();
    grid.add(PlaceResource(kind));
    await settle();
  }

  Future<void> create() async {
    cubit.open();
    cubit.changeName('Persistent smoke');
    await cubit.submit();
    await settle();
  }

  Future<void> open() async {
    cubit.openExisting();
    cubit.changeOpenId(id);
    await cubit.submit();
    await settle();
  }

  test('create empty Design, save confirmed snapshot, repeat does not POST',
      () async {
    await create();
    expect(cubit.state.canSave, false);
    await place();
    expect(cubit.state.canSave, true);
    await cubit.save();
    expect(cubit.state.saved, true);
    expect(resources.posts, 1);
    expect(resources.gets, 2);
    await cubit.save();
    expect(resources.posts, 1);
    expect(cubit.state.canSave, false);
  });
  test('pending save and double-click cannot duplicate writes', () async {
    await create();
    await place();
    resources.pending = Completer<void>();
    final saving = cubit.save();
    await settle();
    expect(cubit.state.pending, true);
    expect(cubit.state.saved, false);
    await cubit.save();
    expect(resources.posts, 1);
    cubit.openExisting();
    cubit.open();
    expect(cubit.state.dialogOpen, false);
    resources.pending!.complete();
    await saving;
    expect(cubit.state.saved, true);
  });
  test(
      'ambiguous empty read never enables a blind duplicate, even after reopening dialog',
      () async {
    await create();
    await place();
    resources.ambiguous = true;
    await cubit.save();
    expect(cubit.state.saveUncertain, true);
    expect(cubit.state.saved, false);
    expect(grid.state.tiles, {pos: ResourceKind.cloudStorage});
    for (var i = 0; i < 3; i++) {
      await cubit.save();
    }
    expect(resources.posts, 1);
    cubit.openExisting();
    cubit.changeOpenId(id);
    cubit.approveDiscard(true);
    await cubit.submit();
    expect(cubit.state.dialogOpen, true);
    expect(cubit.state.error, contains('unknown'));
    cubit.cancel();
    await cubit.save();
    expect(resources.posts, 1);
  });
  test('lost POST response after commit reconciles with GET only', () async {
    await create();
    await place();
    resources
      ..ambiguous = true
      ..loseAfterCommit = true;
    await cubit.save();
    expect(cubit.state.saveUncertain, true);
    await cubit.save();
    expect(cubit.state.saved, true);
    expect(cubit.state.saveUncertain, false);
    expect(resources.posts, 1);
  });
  test(
      '201 followed by failed read-back remains unconfirmed and recovers without POST',
      () async {
    await create();
    await place();
    resources.pending = Completer<void>();
    final saving = cubit.save();
    await settle();
    resources.failRead = true;
    resources.pending!.complete();
    await saving;
    expect(cubit.state.saved, false);
    expect(cubit.state.saveUncertain, true);
    resources.failRead = false;
    await cubit.save();
    expect(cubit.state.saved, true);
    expect(resources.posts, 1);
  });
  test('definite rejection preserves cube and permits guarded recovery',
      () async {
    await create();
    await place();
    resources.reject = true;
    await cubit.save();
    expect(cubit.state.saved, false);
    expect(cubit.state.saveUncertain, false);
    expect(cubit.state.canSave, true);
    expect(grid.state.tiles[pos], ResourceKind.cloudStorage);
    resources.reject = false;
    await cubit.save();
    expect(resources.posts, 2);
    expect(cubit.state.saved, true);
  });
  test(
      'open after complete Cubit/grid disposal restores one cube with no writes',
      () async {
    resources.records = [row];
    await cubit.close();
    await grid.close();
    grid = IsomapGridBloc();
    cubit = DesignCubit(designs, grid, resources: resources);
    await open();
    expect(cubit.state.active, design);
    expect(cubit.state.saved, true);
    expect(grid.state.tiles, {pos: ResourceKind.cloudStorage});
    expect(grid.state.selected, isNull);
    expect(resources.posts, 0);
  });
  test('failed Open never discards local placements or replaces active Design',
      () async {
    await create();
    await place(ResourceKind.cloudVpn);
    final before = grid.state;
    cubit.openExisting();
    cubit.changeOpenId(id);
    await cubit.submit();
    expect(resources.gets, 0);
    cubit.approveDiscard(true);
    designs.fail = true;
    await cubit.submit();
    expect(grid.state, before);
    expect(cubit.state.active, design);
    expect(cubit.state.error, isNotNull);
    designs.fail = false;
    resources.failRead = true;
    await cubit.submit();
    expect(grid.state, before);
  });
  test('invalid IDs, empty Design and unsupported saves are predictable',
      () async {
    cubit.openExisting();
    cubit.changeOpenId('bad');
    await cubit.submit();
    expect(designs.gets, 0);
    cubit.cancel();
    await open();
    expect(grid.state.tiles, isEmpty);
    await place(ResourceKind.computeEngine);
    expect(cubit.state.canSave, false);
    await cubit.save();
    expect(resources.posts, 0);
    await place();
    grid.add(const TileClicked(GridPos(0, 0)));
    await settle();
    grid.add(const PlaceResource(ResourceKind.cloudStorage));
    await settle();
    expect(cubit.state.canSave, true);
    expect(grid.state.resources, hasLength(2));
  });
  test('unrelated existing resource is not adopted solely by its tile',
      () async {
    await create();
    await place();
    resources.records = [row];
    await cubit.save();
    expect(cubit.state.saved, false);
    expect(cubit.state.persistenceMessage, contains('unrelated'));
    expect(resources.posts, 0);
  });
  test('local changes during save stay unsaved, snapshot is immutable',
      () async {
    await create();
    await place();
    resources.pending = Completer<void>();
    final saving = cubit.save();
    await settle();
    await place(ResourceKind.cloudVpn);
    resources.pending!.complete();
    await saving;
    expect(resources.records.single.position, pos);
    expect(grid.state.tiles[pos], ResourceKind.cloudVpn);
    expect(cubit.state.saved, false);
    expect(cubit.state.canSave, false);
  });
  test(
      '201 with an empty read-back remains unknown until positive reconciliation',
      () async {
    await create();
    await place();
    resources.staleRead = true;
    await cubit.save();
    expect(cubit.state.saved, false);
    expect(cubit.state.saveUncertain, true);
    await cubit.save();
    expect(resources.posts, 1);
    resources.staleRead = false;
    await cubit.save();
    expect(cubit.state.saved, true);
    expect(resources.posts, 1);
  });
  test('failed Design read-back after POST is not confirmed or blindly retried',
      () async {
    await create();
    await place();
    resources.pending = Completer<void>();
    final saving = cubit.save();
    await settle();
    designs.fail = true;
    resources.pending!.complete();
    await saving;
    expect(cubit.state.saved, false);
    expect(cubit.state.saveUncertain, true);
    designs.fail = false;
    await cubit.save();
    expect(cubit.state.saved, true);
    expect(resources.posts, 1);
  });
  test(
      'shutdown ignores late save/read results and cancels the grid subscription',
      () async {
    await create();
    await place();
    resources.pending = Completer<void>();
    final saving = cubit.save();
    await settle();
    final before = grid.state;
    await cubit.close();
    resources.pending!.complete();
    await saving;
    expect(grid.state, before);
    expect(cubit.isClosed, true);
    expect(designs.gets, 1);
  });

  Future<void> placeAt(GridPos p,
      [ResourceKind kind = ResourceKind.cloudStorage]) async {
    grid.add(TileClicked(p));
    await settle();
    grid.add(PlaceResource(kind));
    await settle();
  }

  ResourceConfiguration config(String bucket) =>
      ResourceConfiguration(schemaVersion: 1, values: {
        'projectId': 'example-project-123',
        'bucketName': bucket,
        'location': 'europe-west9'
      });

  test(
      'two placements retain local identity, distinct server IDs and repeated Save is a no-op',
      () async {
    await create();
    await placeAt(pos);
    await placeAt(const GridPos(4, 1));
    final localKeys =
        grid.state.resources.map((p, r) => MapEntry(p, r.localKey));
    resources.pending = Completer<void>();
    final saving = cubit.save();
    await settle();
    await cubit.save();
    expect(resources.posts, 1);
    resources.pending!.complete();
    await saving;
    expect(cubit.state.saved, true);
    expect(resources.posts, 2);
    expect(resources.records.map((r) => r.id).toSet(), hasLength(2));
    expect(
        grid.state.resources.map((p, r) => MapEntry(p, r.localKey)), localKeys);
    expect(
        grid.state.resources.values
            .every((r) => r.id != null && r.configuration == null),
        true);
    expect(cubit.state.persistenceMessage, contains('Unconfigured: 2'));
    await cubit.save();
    expect(resources.posts, 2);
  });

  test(
      'one rejected member preserves confirmed sibling and retries only the unsaved member',
      () async {
    await create();
    await placeAt(pos);
    await placeAt(const GridPos(4, 1));
    resources.rejectPostNumber = 2;
    await cubit.save();
    final firstId = grid.state.resources[pos]!.id;
    expect(firstId, isNotNull);
    expect(cubit.state.saved, false);
    expect(cubit.state.saveUncertain, false);
    expect(grid.state.resources[const GridPos(4, 1)]!.id, isNull);
    expect(resources.records, hasLength(1));
    resources.rejectPostNumber = 0;
    await cubit.save();
    expect(cubit.state.saved, true);
    expect(resources.records, hasLength(2));
    expect(resources.posts, 3);
    expect(grid.state.resources[pos]!.id, firstId);
  });

  test(
      'lost second POST response reconciles both placements without another write',
      () async {
    await create();
    await placeAt(pos);
    await placeAt(const GridPos(4, 1));
    final secondKey = grid.state.resources[const GridPos(4, 1)]!.localKey;
    resources.unknownPostNumber = 2;
    resources.loseAfterCommit = true;
    await cubit.save();
    expect(cubit.state.saved, false);
    expect(cubit.state.saveUncertain, true);
    expect(resources.records, hasLength(2));
    await cubit.save();
    expect(cubit.state.saved, true);
    expect(grid.state.resources[const GridPos(4, 1)]!.localKey, secondKey);
    expect(resources.posts, 2);
    expect(resources.puts, 0);
  });

  test(
      'fresh grid/Cubit and repeated Open restore every ID without creating rows',
      () async {
    await create();
    await placeAt(pos);
    await placeAt(const GridPos(4, 1));
    await cubit.save();
    final ids = grid.state.resources.map((p, r) => MapEntry(p, r.id));
    await cubit.close();
    await grid.close();
    grid = IsomapGridBloc();
    cubit = DesignCubit(designs, grid, resources: resources);
    await open();
    expect(cubit.state.saved, true);
    expect(grid.state.resources.map((p, r) => MapEntry(p, r.id)), ids);
    await open();
    expect(grid.state.resources.map((p, r) => MapEntry(p, r.id)), ids);
    expect(resources.posts, 2);
  });

  test(
      'configuration-only edit is dirty and saves without changing identity or kind',
      () async {
    resources.records = [
      PersistedResource(
          id: rid,
          designId: id,
          position: pos,
          catalogId: catalogId,
          revision: 3,
          etag: '"revision3"',
          configuration: config('bucket-original'),
          configurationState: 'validated')
    ];
    await open();
    final tiles = grid.state.tiles;
    grid.add(ChangeResourceConfiguration(pos, config('bucket-edited')));
    await settle();
    expect(grid.state.tiles, tiles);
    expect(cubit.state.saved, false);
    await cubit.save();
    expect(resources.posts, 0);
    expect(resources.puts, 1);
    expect(grid.state.resources[pos]!.id, rid);
    expect(grid.state.resources[pos]!.revision, 4);
    expect(cubit.state.saved, true);
    await cubit.save();
    expect(resources.puts, 1);
  });

  test(
      'later draft survives confirmation of an older immutable configuration snapshot',
      () async {
    resources.records = [
      PersistedResource(
          id: rid,
          designId: id,
          position: pos,
          catalogId: catalogId,
          revision: 3,
          etag: '"revision3"',
          configuration: config('bucket-original'),
          configurationState: 'validated')
    ];
    await open();
    grid.add(ChangeResourceConfiguration(pos, config('bucket-sent')));
    await settle();
    resources.pending = Completer<void>();
    final saving = cubit.save();
    await settle();
    grid.add(ChangeResourceConfiguration(pos, config('bucket-later')));
    await settle();
    resources.pending!.complete();
    await saving;
    expect(resources.records.single.configuration, config('bucket-sent'));
    expect(grid.state.resources[pos]!.configuration, config('bucket-later'));
    expect(grid.state.resources[pos]!.revision, 4);
    expect(cubit.state.saved, false);
    await cubit.save();
    expect(cubit.state.saved, true);
    expect(resources.records.single.configuration, config('bucket-later'));
  });

  test(
      'persisted replacement and deletion cannot silently rewrite saved resources',
      () async {
    resources.records = [row];
    await open();
    await placeAt(pos, ResourceKind.computeEngine);
    expect(grid.state.tiles[pos], ResourceKind.cloudStorage);
    expect(grid.state.resources[pos]!.id, rid);
    final empty = RestoreDesignResources.resources({});
    grid.add(empty);
    await empty.applied.future;
    await settle();
    expect(cubit.state.saved, false);
    expect(cubit.state.canSave, false);
    expect(cubit.state.persistenceMessage, contains('Removing or replacing'));
    await cubit.save();
    expect(resources.records, [row]);
    expect(resources.posts, 0);
  });
}

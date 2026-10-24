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

const id = '12345678-1234-1234-1234-123456789abc';
const rid = '22345678-1234-1234-1234-123456789abc';
const pos = GridPos(2, 3);
const design = Design(id: id, name: 'Persistent smoke');
const row = PersistedResource(id: rid, designId: id, position: pos);

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
  int posts = 0, gets = 0;
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
    if (reject) throw const ResourceFailure('Rejected.');
    if (!ambiguous || loseAfterCommit) {
      records = [
        PersistedResource(id: rid, designId: designId, position: position)
      ];
    }
    if (ambiguous) {
      throw const ResourceFailure('Unknown outcome.', ambiguous: true);
    }
    return records.single;
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
    expect(cubit.state.canSave, false);
    expect(cubit.state.persistenceMessage, contains('Only one'));
  });
  test('existing matching resource is adopted rather than duplicated',
      () async {
    await create();
    await place();
    resources.records = [row];
    await cubit.save();
    expect(cubit.state.saved, true);
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
}

import 'dart:async';
import 'package:test/test.dart';
import 'package:blacksmith_front/data/repositories/design_repository.dart';
import 'package:blacksmith_front/domain/bloc/design/design_cubit.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_event.dart';
import 'package:blacksmith_front/domain/models/design.dart';
import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'package:blacksmith_front/domain/models/resource_kind.dart';

class PendingRepository extends DesignRepository {
  PendingRepository() : super(baseUrl: 'http://unused.invalid');
  final submitted = <String>[];
  Completer<Design> pending = Completer<Design>();
  @override
  Future<Design> create(String name) {
    submitted.add(name);
    return pending.future;
  }
}

void main() {
  late PendingRepository repository;
  late IsomapGridBloc grid;
  late DesignCubit cubit;
  const design =
      Design(id: '12345678-1234-1234-1234-123456789abc', name: 'New design');
  setUp(() {
    repository = PendingRepository();
    grid = IsomapGridBloc();
    cubit = DesignCubit(repository, grid);
  });
  tearDown(() async {
    await cubit.close();
    await grid.close();
    repository.close();
  });
  Future<void> place() async {
    grid.add(const TileClicked(GridPos(0, 0)));
    await grid.stream.firstWhere((s) => s.selected != null);
    grid.add(const PlaceResource(ResourceKind.cloudStorage));
    await grid.stream.firstWhere((s) => s.tiles.isNotEmpty);
  }

  test(
      'cancel, invalid name and submission outside a dialog produce no requests',
      () async {
    await cubit.submit();
    cubit.open();
    for (final name in ['', ' ', 'a' * 201]) {
      cubit.changeName(name);
      expect(cubit.state.canSubmit, false);
      await cubit.submit();
    }
    cubit.cancel();
    expect(cubit.state.dialogOpen, false);
    expect(repository.submitted, isEmpty);
    expect(cubit.state.active, isNull);
  });
  test(
      'valid trimmed submission is pending until backend confirmation; duplicates prevented',
      () async {
    cubit.open();
    cubit.changeName('  New design  ');
    final future = cubit.submit();
    expect(cubit.state.pending, true);
    expect(cubit.state.active, isNull);
    expect(cubit.state.canSubmit, false);
    await cubit.submit();
    cubit.cancel();
    cubit.open();
    cubit.changeName('Ignored');
    expect(cubit.state.pending, true);
    expect(repository.submitted, ['New design']);
    repository.pending.complete(design);
    await future;
    expect(cubit.state.active, design);
    expect(cubit.state.dialogOpen, false);
    expect(cubit.state.pending, false);
  });
  test('unsaved placements need explicit consent; cancellation preserves grid',
      () async {
    await place();
    final before = grid.state;
    cubit.open();
    cubit.changeName('New design');
    expect(cubit.state.requiresDiscard, true);
    expect(cubit.state.canSubmit, false);
    await cubit.submit();
    expect(repository.submitted, isEmpty);
    cubit.approveDiscard(true);
    expect(cubit.state.canSubmit, true);
    cubit.cancel();
    expect(grid.state, before);
  });
  test(
      'successful creation clears selection and placements only after API confirmation',
      () async {
    await place();
    final before = grid.state;
    cubit.open();
    cubit.changeName('New design');
    cubit.approveDiscard(true);
    final pending = cubit.submit();
    expect(grid.state, before);
    final cleared =
        grid.stream.firstWhere((s) => s.tiles.isEmpty && s.selected == null);
    repository.pending.complete(design);
    await pending;
    await cleared;
    expect(grid.state.rows, 6);
    expect(grid.state.cols, 6);
    expect(cubit.state.active, design);
  });
  test('late placements also require consent before sending a request',
      () async {
    cubit.open();
    cubit.changeName('New design');
    await place();
    await cubit.submit();
    expect(repository.submitted, isEmpty);
    expect(cubit.state.requiresDiscard, true);
  });
  test(
      'failure preserves placements and previous active Design; explicit retry remains usable',
      () async {
    cubit.open();
    cubit.changeName('New design');
    final first = cubit.submit();
    repository.pending.complete(design);
    await first;
    await Future<void>.delayed(Duration.zero);
    await place();
    final before = grid.state;
    repository.pending = Completer<Design>();
    cubit.open();
    cubit.changeName('Another');
    cubit.approveDiscard(true);
    final second = cubit.submit();
    repository.pending
        .completeError(const DesignFailure('Safe backend failure'));
    await second;
    expect(grid.state, before);
    expect(cubit.state.active, design);
    expect(cubit.state.error, 'Safe backend failure');
    expect(cubit.state.dialogOpen, true);
    expect(cubit.state.canSubmit, true);
    expect(repository.submitted.length, 2);
    cubit.cancel();
    expect(cubit.state.active, design);
    expect(grid.state, before);
  });
  test(
      'shutdown ignores a late result, closes state stream and never resets grid',
      () async {
    await place();
    final before = grid.state;
    var done = false;
    final subscription = cubit.stream.listen((_) {}, onDone: () {
      done = true;
    });
    cubit.open();
    cubit.changeName('New design');
    cubit.approveDiscard(true);
    final pending = cubit.submit();
    await cubit.close();
    repository.pending.complete(design);
    await pending;
    expect(grid.state, before);
    expect(done, true);
    cubit.open();
    cubit.cancel();
    await cubit.submit();
    expect(repository.submitted.length, 1);
    await subscription.cancel();
  });
}

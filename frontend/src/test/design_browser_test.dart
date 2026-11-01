import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:blacksmith_front/data/repositories/design_repository.dart';
import 'package:blacksmith_front/data/repositories/resource_repository.dart';
import 'package:blacksmith_front/domain/bloc/design/design_cubit.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_event.dart';
import 'package:blacksmith_front/domain/models/design.dart';
import 'package:blacksmith_front/domain/models/design_summary.dart';
import 'package:blacksmith_front/domain/models/design_browser_state.dart';
import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'package:blacksmith_front/domain/models/persisted_resource.dart';
import 'package:blacksmith_front/domain/models/resource_kind.dart';
import 'support/fakes.dart';

const first = '11111111-1111-4111-8111-111111111111';
const second = '22222222-2222-4222-8222-222222222222';
const summary = DesignSummary(id: first, name: 'Production infrastructure');
const other = DesignSummary(id: second, name: 'Development');

class Designs extends DesignRepository {
  Designs() : super(baseUrl: 'http://unused.invalid');
  int lists = 0, gets = 0;
  Future<List<DesignSummary>> Function() fetch = () async => [summary, other];
  Future<Design> Function(String) read =
      (id) async => Design(id: id, name: 'Opened');
  @override
  Future<List<DesignSummary>> listDesigns() {
    lists++;
    return fetch();
  }

  @override
  Future<Design> getById(String id) {
    gets++;
    return read(id);
  }

  @override
  Future<Design> create(String name) async => Design(id: first, name: name);
}

class Resources extends ResourceRepository {
  Resources() : super(baseUrl: 'http://unused.invalid');
  int reads = 0;
  Future<List<PersistedResource>> Function() fetch = () async => [];
  @override
  Future<List<PersistedResource>> listForDesign(String id,
      {int rows = 6, int cols = 6}) {
    reads++;
    return fetch();
  }
}

void main() {
  group('GET /designs', () {
    DesignRepository repo(Future<http.Response> Function(http.Request) send,
        {Duration timeout = const Duration(seconds: 1)}) {
      final result = DesignRepository(
          baseUrl: 'http://example.test:5100/base/',
          client: TrackedClient(send),
          requestTimeout: timeout);
      addTearDown(result.close);
      return result;
    }

    test('reads real lightweight metadata once, with name/date fallback',
        () async {
      final calls = <http.Request>[];
      final repository = repo((r) async {
        calls.add(r);
        return http.Response(
            jsonEncode([
              {
                'id': first,
                'name': 'Infrastructure',
                'updatedAtUtc': '2026-10-31T16:00:00Z',
                'description': 'Existing optional metadata'
              },
              {'id': second, 'name': null, 'updatedAtUtc': 'invalid'}
            ]),
            200);
      });
      final entries = await repository.listDesigns();
      expect(calls.single.method, 'GET');
      expect(calls.single.url.path, '/base/designs');
      expect(entries.first.updatedAtUtc, DateTime.utc(2026, 10, 31, 16));
      expect(entries.last.displayName, 'Untitled design');
      expect(entries.last.updatedAtUtc, isNull);
      expect(entries, hasLength(2));
    });
    for (final body in [
      'SECRET',
      '{}',
      '[null]',
      '[{"id":"bad","name":"x"}]',
      jsonEncode([
        {'id': first, 'name': 1}
      ]),
      jsonEncode([
        {'id': first, 'name': 'a'},
        {'id': first.toUpperCase(), 'name': 'b'}
      ]),
      jsonEncode([
        {'id': first, 'name': 'x' * 201}
      ])
    ]) {
      test(
          'rejects malformed/duplicate collection without exposing its body: $body',
          () async {
        await expectLater(
            repo((_) async => http.Response(body, 200)).listDesigns(),
            throwsA(isA<DesignFailure>().having(
                (e) => e.message, 'sanitized', isNot(contains('SECRET')))));
      });
    }
    for (final status in [401, 403, 404, 503]) {
      test('HTTP $status is a safe non-destructive list failure', () async {
        await expectLater(
            repo((_) async => http.Response('SECRET', status)).listDesigns(),
            throwsA(isA<DesignFailure>().having((e) => e.message, 'status',
                allOf(contains('$status'), isNot(contains('SECRET'))))));
      });
    }
    test('timeout and closed client do not retry collection requests',
        () async {
      var calls = 0;
      final pending = Completer<http.Response>();
      final repository = repo((_) {
        calls++;
        return pending.future;
      }, timeout: const Duration(milliseconds: 5));
      await expectLater(
          repository.listDesigns(), throwsA(isA<DesignFailure>()));
      pending.complete(http.Response('[]', 200));
      expect(calls, 1);
      repository.close();
      await expectLater(
          repository.listDesigns(), throwsA(isA<DesignFailure>()));
      expect(calls, 1);
    });
  });

  group('browser lifecycle', () {
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
        Future<void>.delayed(const Duration(milliseconds: 5));
    test(
        'loading is cancelable and search can be entered before metadata arrives',
        () async {
      final list = Completer<List<DesignSummary>>();
      designs.fetch = () => list.future;
      final browsing = cubit.browseDesigns();
      expect(cubit.state.browser.status, DesignListStatus.loading);
      expect(cubit.state.dialogOpen, true);
      expect(cubit.state.pending, false);
      expect(cubit.state.canSubmit, false);
      expect(resources.reads, 0);
      cubit.searchDesigns(' production ');
      list.complete([summary, other]);
      await browsing;
      expect(cubit.state.browser.matches, [summary]);
      expect(cubit.state.openId, isEmpty);
      cubit.selectDesign(first);
      expect(cubit.state.canSubmit, true);
      cubit.searchDesigns('development');
      expect(cubit.state.openId, isEmpty);
      cubit.selectDesign(first);
      expect(cubit.state.openId, isEmpty);
      cubit.selectDesign(second);
      expect(cubit.state.canSubmit, true);
    });
    test('cancel/reopen ignores an older in-flight list completion', () async {
      final old = Completer<List<DesignSummary>>();
      designs.fetch = () => old.future;
      final request = cubit.browseDesigns();
      cubit.cancel();
      designs.fetch = () async => [other];
      await cubit.browseDesigns();
      old.complete([summary]);
      await request;
      expect(cubit.state.browser.entries, [other]);
      expect(cubit.state.active, isNull);
      cubit.cancel();
      expect(cubit.state.dialogOpen, false);
    });
    test(
        'list failure/retry clears stale rows and suppresses duplicate fetches',
        () async {
      designs.fetch = () async => throw const DesignFailure('List unavailable');
      await cubit.browseDesigns();
      expect(cubit.state.browser.status, DesignListStatus.failure);
      expect(cubit.state.browser.error, 'List unavailable');
      final list = Completer<List<DesignSummary>>();
      designs.fetch = () => list.future;
      final retry = cubit.refreshDesigns();
      await cubit.refreshDesigns();
      expect(designs.lists, 2);
      expect(cubit.state.browser.entries, isEmpty);
      list.complete([summary]);
      await retry;
      expect(cubit.state.browser.entries, [summary]);
    });
    test('sorts updated metadata and bounds each rendered page to fifty rows',
        () async {
      final entries = List.generate(
          121,
          (i) => DesignSummary(
              id: '33333333-3333-4333-8333-${i.toString().padLeft(12, '0')}',
              name: 'Design $i',
              updatedAtUtc: DateTime.utc(2026, 10, 31, 0, i)));
      designs.fetch = () async => entries;
      await cubit.browseDesigns();
      expect(cubit.state.browser.pageEntries, hasLength(50));
      expect(cubit.state.browser.entries.first, entries.last);
      cubit.selectDesign(entries.last.id);
      expect(cubit.state.canSubmit, true);
      cubit.changeDesignPage(1);
      expect(cubit.state.openId, isEmpty);
      expect(cubit.state.browser.pageEntries, hasLength(50));
      cubit.changeDesignPage(2);
      expect(cubit.state.browser.pageEntries, hasLength(21));
      cubit.changeDesignPage(3);
      expect(cubit.state.browser.page, 2);
      cubit.searchDesigns('DESIGN 120');
      expect(cubit.state.browser.page, 0);
      expect(cubit.state.browser.matches, [entries.last]);
    });
    test('dates absent sort last and fallback names remain searchable',
        () async {
      designs.fetch = () async => [
            const DesignSummary(id: first, name: ' '),
            DesignSummary(
                id: second, name: 'Z', updatedAtUtc: DateTime.utc(2026))
          ];
      await cubit.browseDesigns();
      expect(cubit.state.browser.entries.first.id, second);
      cubit.searchDesigns('untitled');
      expect(cubit.state.browser.matches.single.id, first);
    });
    test(
        'opening waits for canonical resources, prevents duplicates and closes only on success',
        () async {
      final rows = Completer<List<PersistedResource>>();
      resources.fetch = () => rows.future;
      await cubit.browseDesigns();
      cubit.selectDesign(first);
      final opening = cubit.submit();
      await settle();
      expect(cubit.state.pending, true);
      expect(cubit.state.active, isNull);
      await cubit.submit();
      cubit.cancel();
      expect(designs.gets, 1);
      expect(resources.reads, 1);
      expect(cubit.state.dialogOpen, true);
      rows.complete([
        const PersistedResource(
            id: second, designId: first, position: GridPos(1, 2))
      ]);
      await opening;
      expect(cubit.state.active?.id, first);
      expect(cubit.state.dialogOpen, false);
      expect(grid.state.tiles[const GridPos(1, 2)], ResourceKind.cloudStorage);
    });
    test(
        'failed open retains workspace/selection and can be retried without relisting',
        () async {
      cubit.open();
      cubit.changeName('Current');
      await cubit.submit();
      grid.add(const TileClicked(GridPos(2, 3)));
      await settle();
      grid.add(const PlaceResource(ResourceKind.computeEngine));
      await settle();
      final old = cubit.state.active;
      final snapshot = grid.state;
      await cubit.browseDesigns();
      cubit.selectDesign(second);
      expect(cubit.state.requiresDiscard, true);
      expect(cubit.state.canSubmit, false);
      await cubit.submit();
      expect(designs.gets, 0);
      cubit.approveDiscard(true);
      designs.read = (_) async => throw const DesignFailure('Open unavailable');
      await cubit.submit();
      expect(cubit.state.active, old);
      expect(grid.state, snapshot);
      expect(cubit.state.error, 'Open unavailable');
      expect(cubit.state.dialogOpen, true);
      expect(cubit.state.openId, second);
      expect(cubit.state.canSubmit, true);
      designs.read = (id) async => Design(id: id, name: 'Replacement');
      await cubit.submit();
      expect(cubit.state.active?.id, second);
      expect(grid.state.resources, isEmpty);
      expect(designs.lists, 1);
    });
    test('close ignores late catalog results', () async {
      final list = Completer<List<DesignSummary>>();
      designs.fetch = () => list.future;
      final browsing = cubit.browseDesigns();
      await cubit.close();
      list.complete([summary]);
      await browsing;
      expect(cubit.isClosed, true);
    });
  });
}

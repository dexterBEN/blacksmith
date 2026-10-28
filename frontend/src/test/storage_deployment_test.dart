import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:blacksmith_front/data/repositories/resource_repository.dart';
import 'package:blacksmith_front/domain/bloc/design/design_cubit.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_event.dart';
import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'package:blacksmith_front/domain/models/resource_kind.dart';
import 'package:blacksmith_front/domain/models/persisted_resource.dart';
import 'package:blacksmith_front/domain/models/placed_resource.dart';
import 'package:blacksmith_front/domain/models/storage_deployment.dart';
import 'resource_configuration_workflow_test.dart' as configuration;
import 'design_persistence_test.dart' as fixtures;

const token = 'fixture-local-token-never-used-for-real-cloud-0000';
const operation = '92345678-1234-1234-1234-123456789abc';
const document =
    '''{"schemaVersion":1,"configuration":{"projectId":"example-project-123","bucketName":"blacksmith-deployment-fixture","location":"europe-west9"}}''';

class Deployments extends configuration.ConfiguredResources {
  int deploys = 0, inspections = 0, retries = 0;
  bool loseResponse = false;
  String outcome = 'succeeded';
  @override
  bool get deploymentEnabled => true;
  PersistedResource attach(PersistedResource record, String id, String status) {
    final value = PersistedResource(
        id: record.id,
        designId: record.designId,
        position: record.position,
        name: record.name,
        catalogId: record.catalogId,
        revision: record.revision,
        etag: record.etag,
        configuration: record.configuration,
        configurationState: record.configurationState,
        deployment: StorageDeployment(
            id: id,
            resourceId: record.id,
            designId: record.designId,
            resourceRevision: record.revision,
            projectId: 'example-project-123',
            bucketName: record.configuration!.values['bucketName'] as String,
            location: 'europe-west9',
            status: status,
            code: switch (status) {
              'succeeded' => 'verified',
              'pending' => 'deploying',
              'failed' => 'provider_rejected',
              _ => 'provider_timeout',
            },
            ownershipVerified: status == 'succeeded'));
    records = [...records.where((r) => r.id != record.id), value];
    return value;
  }

  @override
  Future<PersistedResource> saveAndDeploy(String designId, GridPos position,
      PlacedResource intent, String operationId,
      {required bool consent, int rows = 6, int cols = 6}) async {
    expect(consent, isTrue);
    deploys++;
    final record = await writeConfigured(designId, position, intent);
    final value = attach(record, operationId, outcome);
    if (loseResponse) {
      throw const ResourceFailure('Lost response.', ambiguous: true);
    }
    return value;
  }

  @override
  Future<StorageDeployment> checkDeployment(
      String designId, String resourceId, String operationId,
      {bool reconcile = false}) async {
    if (reconcile) inspections++;
    final record = await getById(designId, resourceId);
    if (!reconcile) return record.deployment!;
    return attach(record, operationId, 'succeeded').deployment!;
  }

  @override
  Future<StorageDeployment> retryDeployment(String designId,
      PlacedResource resource, String operationId, String requestId,
      {required bool consent}) async {
    expect(consent, isTrue);
    retries++;
    return attach(
            await getById(designId, resource.id!), operationId, 'succeeded')
        .deployment!;
  }
}

void main() {
  group('explicit deployment coordinator', () {
    late fixtures.Designs designs;
    late Deployments resources;
    late IsomapGridBloc grid;
    late DesignCubit cubit;
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 10));
    Future<void> open() async {
      cubit.open();
      cubit.changeName('Deploy fixture');
      await cubit.submit();
      grid.add(const TileClicked(fixtures.pos));
      await settle();
      cubit.openResourceConfiguration();
      cubit.changeResourceConfigurationText(document);
    }

    setUp(() {
      designs = fixtures.Designs();
      resources = Deployments();
      grid = IsomapGridBloc();
      cubit = DesignCubit(designs, grid, resources: resources);
    });
    tearDown(() async {
      await cubit.close();
      await grid.close();
      designs.close();
      resources.close();
    });
    test(
        'selection/open/save-only never deploy; consent binds exact current document',
        () async {
      await open();
      await cubit.deployResourceConfiguration();
      expect(resources.deploys, 0);
      cubit.approveDeployment(true);
      expect(cubit.state.configurationDraft!.consent, isTrue);
      cubit.changeResourceConfigurationText('$document ');
      expect(cubit.state.configurationDraft!.consent, isFalse);
      await cubit.saveResourceConfiguration();
      expect(resources.deploys, 0);
      expect(grid.state.resources.length, 1);
      expect(grid.state.resources.values.single.deployment, isNull);
    });
    test(
        'one command; duplicate click blocked; cube bound with durable outcome',
        () async {
      await open();
      cubit.approveDeployment(true);
      resources.pending = Completer<void>();
      final future = cubit.deployResourceConfiguration();
      await settle();
      await cubit.deployResourceConfiguration();
      expect(resources.deploys, 1);
      expect(grid.state.resources, isEmpty);
      resources.pending!.complete();
      await future;
      expect(
          grid.state.resources.values.single.deployment!.status, 'succeeded');
      expect(cubit.state.configurationDraft!.consent, isFalse);
      await cubit.deployResourceConfiguration();
      expect(resources.deploys, 1);
      expect(resources.inspections, 1);
      cubit.cancelResourceConfiguration();
      await cubit.save();
      expect(resources.deploys, 1);
    });
    for (final status in ['failed', 'unknown']) {
      test(
          '$status leaves saved configuration/cube; explicit retry or read-only check',
          () async {
        await open();
        resources.outcome = status;
        cubit.approveDeployment(true);
        await cubit.deployResourceConfiguration();
        final before = grid.state.resources.values.single;
        expect(before.id, isNotNull);
        expect(before.configuration, isNotNull);
        expect(before.deployment!.status, status);
        if (status == 'failed') {
          await cubit.deployResourceConfiguration();
          expect(resources.retries, 0);
          cubit.approveDeployment(true);
        }
        await cubit.deployResourceConfiguration();
        expect(resources.deploys, 1);
        expect(grid.state.resources.values.single.id, before.id);
        expect(
            grid.state.resources.values.single.deployment!.status, 'succeeded');
        expect(resources.retries, status == 'failed' ? 1 : 0);
        expect(resources.inspections, status == 'unknown' ? 1 : 0);
      });
    }
    test(
        'lost HTTP response checks original IDs; no second create; restart restores outcome',
        () async {
      await open();
      resources.loseResponse = true;
      cubit.approveDeployment(true);
      await cubit.deployResourceConfiguration();
      expect(cubit.state.configurationDraft!.uncertain, isTrue);
      expect(resources.deploys, 1);
      final op = cubit.state.configurationDraft!.operationId;
      await cubit.deployResourceConfiguration();
      expect(resources.deploys, 1);
      expect(resources.inspections, 1);
      expect(grid.state.resources.values.single.deployment!.id, op);
      cubit.cancelResourceConfiguration();
      cubit.openExisting();
      cubit.changeOpenId(fixtures.id);
      await cubit.submit();
      expect(
          grid.state.resources.values.single.deployment!.status, 'succeeded');
      expect(resources.deploys, 1);
    });
    test(
        'deploy one resource leaves second Save-only; status change does not conflict with metadata baseline',
        () async {
      await open();
      cubit.approveDeployment(true);
      await cubit.deployResourceConfiguration();
      cubit.cancelResourceConfiguration();
      grid.add(const TileClicked(GridPos(4, 1)));
      await settle();
      cubit.openResourceConfiguration();
      cubit.changeResourceConfigurationText(document.replaceAll(
          'blacksmith-deployment-fixture', 'second-bucket'));
      await cubit.saveResourceConfiguration();
      expect(grid.state.resources.length, 2);
      expect(resources.deploys, 1);
      expect(grid.state.resources[const GridPos(4, 1)]!.deployment, isNull);
    });
    for (final outcome in ['pending', 'succeeded', 'failed', 'unknown']) {
      test(
          'five fresh coordinators restore $outcome and saved-only without writes',
          () async {
        await open();
        resources.outcome = outcome;
        cubit.approveDeployment(true);
        await cubit.deployResourceConfiguration();
        cubit.cancelResourceConfiguration();
        const sibling = GridPos(4, 1);
        grid.add(const TileClicked(sibling));
        await settle();
        cubit.openResourceConfiguration();
        cubit.changeResourceConfigurationText(document.replaceAll(
            'blacksmith-deployment-fixture', 'blacksmith-saved-only'));
        await cubit.saveResourceConfiguration();
        final original = Map.of(grid.state.resources);
        final writes = resources.puts, deploys = resources.deploys;
        final reads = resources.inspections, retries = resources.retries;
        for (var cycle = 0; cycle < 5; cycle++) {
          await cubit.close();
          await grid.close();
          grid = IsomapGridBloc();
          cubit = DesignCubit(designs, grid, resources: resources);
          expect(cubit.state.active, isNull);
          expect(grid.state.resources, isEmpty);
          cubit.openExisting();
          cubit.changeOpenId(fixtures.id);
          await cubit.submit();
          expect(grid.state.resources, original);
          expect(
              grid.state.resources[fixtures.pos]!.deployment!.status, outcome);
          expect(grid.state.resources[sibling]!.deployment, isNull);
          expect(cubit.state.persistenceMessage, contains(outcome));
          grid.add(const TileClicked(fixtures.pos));
          await settle();
          cubit.openResourceConfiguration();
          expect(cubit.state.configurationDraft!.resource.id,
              original[fixtures.pos]!.id);
          expect(cubit.state.configurationDraft!.consent, isFalse);
          cubit.cancelResourceConfiguration();
          expect(resources.puts, writes);
          expect(resources.deploys, deploys);
          expect(resources.inspections, reads);
          expect(resources.retries, retries);
        }
      });
    }
  });
  test('Check Save after a lost deployment response is database-only',
      () async {
    final designs = fixtures.Designs(), resources = Deployments();
    final grid = IsomapGridBloc();
    final cubit = DesignCubit(designs, grid, resources: resources);
    addTearDown(() async {
      await cubit.close();
      await grid.close();
      designs.close();
      resources.close();
    });
    cubit.open();
    cubit.changeName('Metadata-only recovery');
    await cubit.submit();
    grid.add(const TileClicked(fixtures.pos));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    cubit.openResourceConfiguration();
    cubit.changeResourceConfigurationText(document);
    cubit.approveDeployment(true);
    resources.outcome = 'unknown';
    resources.loseResponse = true;
    await cubit.deployResourceConfiguration();
    expect(cubit.state.configurationDraft!.uncertain, isTrue);
    await cubit.saveResourceConfiguration();
    expect(resources.deploys, 1);
    expect(resources.inspections, 0);
    expect(grid.state.resources.values.single.deployment!.status, 'unknown');
    cubit.cancelResourceConfiguration();
    await cubit.save();
    expect(resources.inspections, 0);
  });
  test(
      'editing an already deployed target resets consent and keeps Save-only available',
      () async {
    final designs = fixtures.Designs(), resources = Deployments();
    final grid = IsomapGridBloc();
    final cubit = DesignCubit(designs, grid, resources: resources);
    addTearDown(() async {
      await cubit.close();
      await grid.close();
      designs.close();
      resources.close();
    });
    cubit.open();
    cubit.changeName('Edit deployment');
    await cubit.submit();
    grid.add(const TileClicked(fixtures.pos));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    cubit.openResourceConfiguration();
    cubit.changeResourceConfigurationText(document);
    cubit.approveDeployment(true);
    await cubit.deployResourceConfiguration();
    expect(cubit.checksDeployment, isTrue);
    cubit.changeResourceConfigurationText(document.replaceAll(
        'blacksmith-deployment-fixture', 'new-target-bucket'));
    expect(cubit.checksDeployment, isFalse);
    expect(cubit.state.configurationDraft!.consent, isFalse);
    await cubit.deployResourceConfiguration();
    expect(resources.deploys, 1);
    await cubit.saveResourceConfiguration();
    expect(resources.deploys, 1);
    expect(cubit.state.configurationDraft, isNull);
  });
  test(
      'repository sends one protected PUT with revision, consent and validated target',
      () async {
    var calls = 0;
    final repo = ResourceRepository(
        baseUrl: 'http://localhost:5100',
        deploymentToken: token,
        client: MockClient((request) async {
          calls++;
          expect(request.method, 'PUT');
          expect(request.url.path, contains('/deployments/$operation'));
          expect(request.headers['X-Blacksmith-Deployment-Token'], token);
          expect(request.headers['X-Blacksmith-Deploy-Consent'], 'true');
          expect(request.headers['If-None-Match'], '*');
          expect(request.body, isNot(contains(token)));
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final deployment = {
            'id': operation,
            'resourceId': fixtures.rid,
            'designId': fixtures.id,
            'resourceRevision': 1,
            'projectId': 'example-project-123',
            'bucketName': 'blacksmith-deployment-fixture',
            'location': 'europe-west9',
            'status': 'failed',
            'code': 'provider_rejected',
            'ownershipVerified': false
          };
          final resource = {
            'id': fixtures.rid,
            'designId': fixtures.id,
            'name': body['name'],
            'type': body['type'],
            'resourceTypeId': fixtures.catalogId,
            'x': 3,
            'y': 2,
            'revision': 1,
            'configurationState': 'validated',
            'configuration': {
              'resourceId': fixtures.rid,
              ...body['configuration'] as Map<String, dynamic>
            },
            'deployment': deployment
          };
          return http.Response(
              jsonEncode({'resource': resource, 'deployment': deployment}),
              200);
        }));
    addTearDown(repo.close);
    final intent = PlacedResource(
            localKey: fixtures.rid,
            kind: ResourceKind.cloudStorage,
            catalogId: fixtures.catalogId)
        .withConfiguration(repo.parseConfiguration(document));
    await expectLater(
        repo.saveAndDeploy(fixtures.id, fixtures.pos, intent, operation,
            consent: false),
        throwsA(isA<ResourceFailure>()));
    expect(calls, 0);
    final saved = await repo.saveAndDeploy(
        fixtures.id, fixtures.pos, intent, operation,
        consent: true);
    expect(saved.deployment!.status, 'failed');
    expect(calls, 1);
  });
}

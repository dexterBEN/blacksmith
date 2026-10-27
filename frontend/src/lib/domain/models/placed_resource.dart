import 'storage_deployment.dart';
import 'dart:math';
import 'package:equatable/equatable.dart';
import 'persisted_resource.dart';
import 'resource_configuration.dart';
import 'resource_kind.dart';

/// The grid owns this immutable value; Godot nodes are only rendering caches.
class PlacedResource extends Equatable {
  const PlacedResource(
      {required this.localKey,
      required this.kind,
      this.id,
      this.designId,
      this.catalogId,
      this.name = PersistedResource.displayName,
      this.type = PersistedResource.storageType,
      this.revision,
      this.etag,
      this.configuration,
      this.configurationState = 'absent',
      this.deployment});
  factory PlacedResource.local(ResourceKind kind) =>
      PlacedResource(localKey: newResourceId(), kind: kind);
  factory PlacedResource.fromPersisted(PersistedResource record,
          {String? localKey}) =>
      PlacedResource(
          localKey: localKey ?? record.id,
          kind: ResourceKind.cloudStorage,
          id: record.id,
          designId: record.designId,
          catalogId: record.catalogId,
          name: record.name,
          type: record.type,
          revision: record.revision,
          etag: record.etag,
          configuration: record.configuration,
          configurationState: record.configurationState,
          deployment: record.deployment);
  final String localKey;
  final ResourceKind kind;
  final String? id, designId, catalogId, etag;
  final String name, type, configurationState;
  final int? revision;
  final ResourceConfiguration? configuration;
  final StorageDeployment? deployment;

  PlacedResource withConfiguration(ResourceConfiguration value) =>
      configuration == value
          ? this
          : PlacedResource(
              localKey: localKey,
              kind: kind,
              id: id,
              designId: designId,
              catalogId: catalogId,
              name: name,
              type: type,
              revision: revision,
              etag: etag,
              configuration: value,
              configurationState: 'draft',
              deployment: deployment);

  bool sameSavedContent(PlacedResource other) =>
      localKey == other.localKey &&
      id == other.id &&
      designId == other.designId &&
      catalogId == other.catalogId &&
      revision == other.revision &&
      etag == other.etag &&
      configurationState == other.configurationState &&
      sameContent(other);

  bool sameContent(PlacedResource other) =>
      kind == other.kind &&
      name == other.name &&
      type == other.type &&
      configuration == other.configuration;

  /// Bind server identity/revision without overwriting a newer local draft.
  PlacedResource confirm(PersistedResource record, PlacedResource sent) {
    final canonical = PlacedResource.fromPersisted(record, localKey: localKey);
    if (sameContent(sent)) return canonical;
    return PlacedResource(
        localKey: localKey,
        kind: kind,
        id: record.id,
        designId: record.designId,
        catalogId: record.catalogId,
        name: name,
        type: type,
        revision: record.revision,
        etag: record.etag,
        configuration: configuration,
        configurationState: configurationState,
        deployment: record.deployment);
  }

  @override
  List<Object?> get props => [
        localKey,
        kind,
        id,
        designId,
        catalogId,
        name,
        type,
        revision,
        etag,
        configuration,
        configurationState,
        deployment
      ];
}

/// UUIDv4 for local intent identity, and for future configured conditional creates.
String newResourceId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

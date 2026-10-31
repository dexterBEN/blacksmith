import 'package:equatable/equatable.dart';
import 'dart:async';
import '../../models/placed_resource.dart';
import '../../models/persisted_resource.dart';
import '../../models/resource_configuration.dart';

import '../../models/grid_position.dart';
import '../../models/resource_kind.dart';

abstract class IsomapGridEvent extends Equatable {
  const IsomapGridEvent();

  @override
  List<Object?> get props => [];
}

/// L’utilisateur clique sur une tuile
class TileClicked extends IsomapGridEvent {
  final GridPos pos;
  const TileClicked(this.pos);

  @override
  List<Object?> get props => [pos];
}

/// Deselect without discarding resources, for example when leaving a Design.
class ClearTileSelection extends IsomapGridEvent {
  const ClearTileSelection();
}

/// A semantic palette choice, independent of its Godot texture.
class PlaceResource extends IsomapGridEvent {
  final ResourceKind kind;
  const PlaceResource(this.kind);

  @override
  List<Object?> get props => [kind];
}

/// Sent only after the user approved discarding placements and the API created
/// a new persistent Design. Does not save resources or provision anything.
class ResetGridForNewDesign extends IsomapGridEvent {
  const ResetGridForNewDesign();
}

/// Apply a validated backend snapshot; selection is intentionally cleared.
class RestoreDesignResources extends IsomapGridEvent {
  RestoreDesignResources(Map<GridPos, ResourceKind> tiles)
      : resources = Map.unmodifiable(
            tiles.map((p, kind) => MapEntry(p, PlacedResource.local(kind))));
  RestoreDesignResources.resources(Map<GridPos, PlacedResource> resources)
      : resources = Map.unmodifiable(resources);
  final Map<GridPos, PlacedResource> resources;
  final applied = Completer<bool>();
  @override
  List<Object?> get props => [resources];
}

class ConfirmResourceSaved extends IsomapGridEvent {
  ConfirmResourceSaved(this.position, this.sent, this.record);
  final GridPos position;
  final PlacedResource sent;
  final PersistedResource record;
  final applied = Completer<bool>();
}

/// Publish a verified configured save only if the captured tile is unchanged.
class ApplyConfiguredResource extends IsomapGridEvent {
  ApplyConfiguredResource(
      this.position, this.original, this.intent, this.record);
  final GridPos position;
  final PlacedResource? original;
  final PlacedResource intent;
  final PersistedResource record;
  final applied = Completer<bool>();
}

/// Future configuration UI/test intents; rendering only projects the kind.
class ChangeResourceConfiguration extends IsomapGridEvent {
  const ChangeResourceConfiguration(this.position, this.configuration);
  final GridPos position;
  final ResourceConfiguration configuration;
  @override
  List<Object?> get props => [position, configuration];
}

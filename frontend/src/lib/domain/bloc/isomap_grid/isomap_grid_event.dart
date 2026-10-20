import 'package:equatable/equatable.dart';

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

/// A semantic palette choice, independent of its Godot texture.
class PlaceResource extends IsomapGridEvent {
  final ResourceKind kind;
  const PlaceResource(this.kind);

  @override
  List<Object?> get props => [kind];
}

import 'package:equatable/equatable.dart';
import '../../models/grid_position.dart';

abstract class IsomapGridEvent extends Equatable {
  const IsomapGridEvent();
  @override
  List<Object?> get props => [];
}

/// user click on a tile
class TileClicked extends IsomapGridEvent {
  final GridPos pos;
  const TileClicked(this.pos);

  @override
  List<Object?> get props => [pos];
}

/// Form Step 1 : name validation
class NameSubmitted extends IsomapGridEvent {
  final String name;
  const NameSubmitted(this.name);

  @override
  List<Object?> get props => [name];
}

/// Form Step 2 : resource choice (business)
class PlaceResource extends IsomapGridEvent {
  final String kind; // ex: "gcp:cloud_storage"
  const PlaceResource(this.kind);

  @override
  List<Object?> get props => [kind];
}

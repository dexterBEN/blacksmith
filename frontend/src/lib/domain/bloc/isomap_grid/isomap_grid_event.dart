import 'package:equatable/equatable.dart';

import '../../models/grid_position.dart';


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

/// L’utilisateur choisit une ressource dans le menu
/// `path` = chemin d’asset Godot
class PlaceResource extends IsomapGridEvent {
  final String path;
  const PlaceResource(this.path);

  @override
  List<Object?> get props => [path];
}

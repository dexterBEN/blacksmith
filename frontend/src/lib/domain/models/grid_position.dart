import 'package:equatable/equatable.dart';

class GridPos extends Equatable {
  final int row;
  final int col;

  const GridPos(this.row, this.col);

  @override
  List<Object> get props => [row, col];

  @override
  String toString() => '($row,$col)';
}


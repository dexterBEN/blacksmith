import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../data/repositories/design_repository.dart';
import '../../models/design.dart';
import '../isomap_grid/isomap_grid_bloc.dart';
import '../isomap_grid/isomap_grid_event.dart';

enum DesignStatus { editing, submitting, failure }

class DesignState extends Equatable {
  const DesignState(
      {this.active,
      this.dialogOpen = false,
      this.name = '',
      this.status = DesignStatus.editing,
      this.error,
      this.requiresDiscard = false,
      this.discardApproved = false});
  final Design? active;
  final bool dialogOpen;
  final String name;
  final DesignStatus status;
  final String? error;
  final bool requiresDiscard;
  final bool discardApproved;
  bool get pending => status == DesignStatus.submitting;
  bool get canSubmit =>
      dialogOpen &&
      !pending &&
      Design.validateName(name) == null &&
      (!requiresDiscard || discardApproved);

  DesignState copyWith(
          {Design? active,
          bool? dialogOpen,
          String? name,
          DesignStatus? status,
          String? error,
          bool? requiresDiscard,
          bool? discardApproved}) =>
      DesignState(
          active: active ?? this.active,
          dialogOpen: dialogOpen ?? this.dialogOpen,
          name: name ?? this.name,
          status: status ?? this.status,
          error: error,
          requiresDiscard: requiresDiscard ?? this.requiresDiscard,
          discardApproved: discardApproved ?? this.discardApproved);
  @override
  List<Object?> get props => [
        active,
        dialogOpen,
        name,
        status,
        error,
        requiresDiscard,
        discardApproved
      ];
}

/// Coordinates Design creation and an explicitly approved empty local grid.
/// Tile selection/placement and all HTTP/JSON details stay in their owners.
class DesignCubit extends Cubit<DesignState> {
  DesignCubit(this._repository, this._grid) : super(const DesignState());
  final DesignRepository _repository;
  final IsomapGridBloc _grid;

  void open() {
    if (isClosed || state.pending) return;
    emit(DesignState(
        active: state.active,
        dialogOpen: true,
        requiresDiscard: _grid.state.tiles.isNotEmpty));
  }

  void changeName(String value) {
    if (isClosed || !state.dialogOpen || state.pending) return;
    emit(state.copyWith(
        name: value,
        status: DesignStatus.editing,
        error: Design.validateName(value)));
  }

  void approveDiscard(bool approved) {
    if (!isClosed && state.dialogOpen && !state.pending) {
      emit(state.copyWith(discardApproved: approved));
    }
  }

  void cancel() {
    // A pending POST cannot be safely cancelled/retried: it may already persist.
    if (isClosed || state.pending) return;
    emit(DesignState(active: state.active));
  }

  Future<void> submit() async {
    if (isClosed || !state.dialogOpen || state.pending) return;
    final invalid = Design.validateName(state.name);
    final hasPlacements = _grid.state.tiles.isNotEmpty;
    if (invalid != null || (hasPlacements && !state.discardApproved)) {
      emit(state.copyWith(
          error: invalid ?? 'Confirm clearing the unsaved local placements.',
          requiresDiscard: hasPlacements));
      return;
    }
    final name = state.name.trim();
    emit(state.copyWith(status: DesignStatus.submitting));
    try {
      final design = await _repository.create(name);
      if (isClosed) return; // Shutdown must not mutate a disposed editor.
      _grid.add(const ResetGridForNewDesign());
      emit(DesignState(active: design));
    } on DesignFailure catch (failure) {
      if (!isClosed) {
        emit(state.copyWith(
            status: DesignStatus.failure, error: failure.message));
      }
    } on Exception {
      if (!isClosed) {
        emit(state.copyWith(
            status: DesignStatus.failure,
            error:
                'Design creation could not be confirmed. Check the API before submitting again.'));
      }
    }
  }
}

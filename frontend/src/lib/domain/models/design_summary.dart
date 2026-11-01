import 'package:equatable/equatable.dart';

/// Lightweight metadata supplied by GET /designs, without resource payloads.
class DesignSummary extends Equatable {
  const DesignSummary(
      {required this.id, required this.name, this.updatedAtUtc});
  final String id, name;
  final DateTime? updatedAtUtc;
  String get displayName =>
      name.trim().isEmpty ? 'Untitled design' : name.trim();
  @override
  List<Object?> get props => [id, name, updatedAtUtc];
}

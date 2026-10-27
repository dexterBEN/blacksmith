import 'package:equatable/equatable.dart';
import 'grid_position.dart';
import 'placed_resource.dart';

/// One modal editing session, not a renderable placement or another grid map.
class ResourceConfigurationDraft extends Equatable {
  const ResourceConfigurationDraft(
      {required this.designId,
      required this.position,
      required this.resource,
      required this.text,
      this.original,
      this.error,
      this.uncertain = false,
      this.consent = false,
      this.operationId,
      this.deploymentCommand = false});
  final String designId;
  final GridPos position;
  final PlacedResource resource;
  final PlacedResource? original;
  final String text;
  final String? error;
  final bool uncertain, consent, deploymentCommand;
  final String? operationId;
  ResourceConfigurationDraft copyWith(
          {String? text,
          String? error,
          bool? uncertain,
          bool? consent,
          String? operationId,
          bool? deploymentCommand}) =>
      ResourceConfigurationDraft(
          designId: designId,
          position: position,
          resource: resource,
          original: original,
          text: text ?? this.text,
          error: error,
          uncertain: uncertain ?? this.uncertain,
          consent: consent ?? this.consent,
          operationId: operationId ?? this.operationId,
          deploymentCommand: deploymentCommand ?? this.deploymentCommand);
  @override
  List<Object?> get props => [
        designId,
        position,
        resource,
        original,
        text,
        error,
        uncertain,
        consent,
        operationId,
        deploymentCommand
      ];
}

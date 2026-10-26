import 'package:equatable/equatable.dart';

/// A nonsecret document value. The backend remains the validation authority.
class ResourceConfiguration extends Equatable {
  ResourceConfiguration(
      {required this.schemaVersion, required Map<String, dynamic> values})
      : values = _freeze(schemaVersion == 1
            ? <String, dynamic>{
                'storageClass': 'STANDARD',
                'uniformBucketLevelAccess': true,
                'publicAccessPrevention': 'enforced',
                ...values
              }
            : values) as Map<String, dynamic>;
  final int schemaVersion;
  final Map<String, dynamic> values;
  static dynamic _freeze(dynamic value) => switch (value) {
        Map<String, dynamic> map => Map<String, dynamic>.unmodifiable(
            map.map((key, item) => MapEntry(key, _freeze(item)))),
        List<dynamic> list => List<dynamic>.unmodifiable(list.map(_freeze)),
        _ => value,
      };
  @override
  List<Object?> get props => [schemaVersion, values];
}

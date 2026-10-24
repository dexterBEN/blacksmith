import 'package:equatable/equatable.dart';

class Design extends Equatable {
  const Design({required this.id, required this.name});
  final String id;
  final String name;

  static String? validateName(String name) {
    if (name.trim().isEmpty) return 'Enter a Design name.';
    // Dart and .NET both count UTF-16 code units here.
    if (name.trim().length > 200) return 'Use at most 200 characters.';
    return null;
  }

  @override
  List<Object?> get props => [id, name];
}

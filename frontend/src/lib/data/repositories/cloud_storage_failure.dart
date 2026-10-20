/// A safe operation failure suitable for presentation without raw responses.
class CloudStorageFailure implements Exception {
  const CloudStorageFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

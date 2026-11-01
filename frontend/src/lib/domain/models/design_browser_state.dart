import 'package:equatable/equatable.dart';
import 'design_summary.dart';

enum DesignListStatus { idle, loading, ready, failure }

/// Part of DesignState: metadata/query/page only. Selection remains openId.
class DesignBrowserState extends Equatable {
  const DesignBrowserState(
      {this.status = DesignListStatus.idle,
      this.entries = const [],
      this.query = '',
      this.page = 0,
      this.error});
  static const pageSize = 50;
  final DesignListStatus status;
  final List<DesignSummary> entries;
  final String query;
  final int page;
  final String? error;

  List<DesignSummary> get matches {
    final text = query.trim().toLowerCase();
    return text.isEmpty
        ? entries
        : entries
            .where((d) => d.displayName.toLowerCase().contains(text))
            .toList(growable: false);
  }

  int get pageCount => (matches.length / pageSize).ceil();
  List<DesignSummary> get pageEntries =>
      matches.skip(page * pageSize).take(pageSize).toList(growable: false);
  DesignBrowserState copyWith(
          {DesignListStatus? status,
          List<DesignSummary>? entries,
          String? query,
          int? page,
          String? error}) =>
      DesignBrowserState(
          status: status ?? this.status,
          entries: entries ?? this.entries,
          query: query ?? this.query,
          page: page ?? this.page,
          error: error);

  static List<DesignSummary> sorted(Iterable<DesignSummary> entries) =>
      List.unmodifiable(entries.toList()
        ..sort((a, b) {
          final first = a.updatedAtUtc, second = b.updatedAtUtc;
          final date = first == null
              ? (second == null ? 0 : 1)
              : second == null
                  ? -1
                  : second.compareTo(first);
          if (date != 0) return date;
          final name = a.displayName
              .toLowerCase()
              .compareTo(b.displayName.toLowerCase());
          return name == 0 ? a.id.compareTo(b.id) : name;
        }));
  @override
  List<Object?> get props => [status, entries, query, page, error];
}

class CronJobList {
  const CronJobList({required this.names});

  final List<String> names;

  factory CronJobList.fromJson(Map<String, dynamic> json) {
    final raw = json['names'];
    return CronJobList(
      names: raw is List ? [for (final e in raw) e as String] : const [],
    );
  }

  Map<String, dynamic> toJson() => {'names': names};
}

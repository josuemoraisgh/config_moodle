class MoodleCredential {
  final String moodleUrl;
  final String username;
  final String token;
  final int userId;
  final String fullname;
  final DateTime savedAt;

  MoodleCredential({
    required this.moodleUrl,
    required this.username,
    required this.token,
    required this.userId,
    required this.fullname,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
    'moodleUrl': moodleUrl,
    'username': username,
    'token': token,
    'userId': userId,
    'fullname': fullname,
    'savedAt': savedAt.toIso8601String(),
  };

  factory MoodleCredential.fromJson(Map<String, dynamic> json) =>
      MoodleCredential(
        moodleUrl: json['moodleUrl'] as String,
        username: json['username'] as String,
        token: json['token'] as String,
        userId: json['userId'] as int,
        fullname: json['fullname'] as String,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}

class MoodleCourse {
  final int id;
  final String shortname;
  final String fullname;

  MoodleCourse({
    required this.id,
    required this.shortname,
    required this.fullname,
  });

  factory MoodleCourse.fromJson(Map<String, dynamic> json) => MoodleCourse(
    id: json['id'] as int,
    shortname: json['shortname'] as String? ?? '',
    fullname: json['fullname'] as String? ?? '',
  );
}

class MoodleSection {
  final int id;
  final int section;
  final String name;
  final String summary;
  final bool visible;
  final List<MoodleModule> modules;

  MoodleSection({
    required this.id,
    required this.section,
    required this.name,
    required this.summary,
    required this.visible,
    required this.modules,
  });

  factory MoodleSection.fromJson(Map<String, dynamic> json) => MoodleSection(
    id: json['id'] as int,
    section: json['section'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    visible: (json['visible'] as int?) == 1,
    modules:
        (json['modules'] as List?)
            ?.map((m) => MoodleModule.fromJson(m as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

class MoodleModule {
  final int id;
  final String name;
  final String modname; // assign, quiz, resource, etc.
  final bool visible;
  final List<MoodleDate> dates;

  MoodleModule({
    required this.id,
    required this.name,
    required this.modname,
    required this.visible,
    required this.dates,
  });

  factory MoodleModule.fromJson(Map<String, dynamic> json) => MoodleModule(
    id: json['id'] as int,
    name: json['name'] as String? ?? '',
    modname: json['modname'] as String? ?? '',
    visible: (json['visible'] as int?) == 1,
    dates:
        (json['dates'] as List?)
            ?.map((d) => MoodleDate.fromJson(d as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

class MoodleDate {
  final String label;
  final int timestamp;
  final String dataid;

  MoodleDate({required this.label, required this.timestamp, this.dataid = ''});

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);

  /// Verifica se esta data representa uma data de abertura/início.
  bool get isOpenDate {
    final id = dataid.toLowerCase();
    final lbl = label.toLowerCase();
    return id.contains('allowsubmissionsfromdate') ||
        id.contains('timeopen') ||
        id.contains('available') ||
        id == 'open' ||
        id.contains('start') ||
        lbl.contains('open') ||
        lbl.contains('abert') ||
        lbl.contains('início') ||
        lbl.contains('inicio') ||
        lbl.contains('disponível') ||
        lbl.contains('disponivel') ||
        lbl.contains('start');
  }

  /// Verifica se esta data representa uma data de fechamento/fim.
  bool get isCloseDate {
    final id = dataid.toLowerCase();
    final lbl = label.toLowerCase();
    return id.contains('duedate') ||
        id.contains('timeclose') ||
        id.contains('cutoffdate') ||
        id.contains('deadline') ||
        id.contains('end') ||
        id == 'close' ||
        lbl.contains('due') ||
        lbl.contains('close') ||
        lbl.contains('encerr') ||
        lbl.contains('vencimento') ||
        lbl.contains('prazo') ||
        lbl.contains('entrega') ||
        lbl.contains('término') ||
        lbl.contains('termino') ||
        lbl.contains('fim') ||
        lbl.contains('end');
  }

  factory MoodleDate.fromJson(Map<String, dynamic> json) => MoodleDate(
    label: json['label'] as String? ?? '',
    timestamp: json['timestamp'] as int? ?? 0,
    dataid: json['dataid'] as String? ?? '',
  );
}

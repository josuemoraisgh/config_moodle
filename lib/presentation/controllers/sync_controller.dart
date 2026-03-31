import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:config_moodle/core/utils/string_matcher.dart';
import 'package:config_moodle/domain/entities/course_config.dart';
import 'package:config_moodle/domain/entities/moodle_entities.dart';
import 'package:config_moodle/domain/repositories/i_moodle_repository.dart';

class SyncController extends ChangeNotifier {
  final IMoodleRepository _repo;

  SyncController(this._repo);

  List<MoodleCourse> _courses = [];
  List<MoodleSection> _moodleSections = [];
  List<SectionMatch> _matches = [];
  bool _loading = false;
  String? _error;
  double _progress = 0;
  String _progressMessage = '';
  bool _syncing = false;

  List<MoodleCourse> get courses => _courses;
  List<MoodleSection> get moodleSections => _moodleSections;
  List<SectionMatch> get matches => _matches;
  bool get loading => _loading;
  String? get error => _error;
  double get progress => _progress;
  String get progressMessage => _progressMessage;
  bool get syncing => _syncing;

  Future<void> loadCourses(String token, String baseUrl) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _courses = await _repo.getCourses(token, baseUrl);
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadMoodleSections(
      String token, String baseUrl, int courseId) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _moodleSections = await _repo.getCourseContents(token, baseUrl, courseId);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  /// Gera correspondências entre seções locais e seções do Moodle usando
  /// similaridade de nomes (Jaro-Winkler).
  void generateMatches(CourseConfig config) {
    _matches = [];
    final moodleNames = _moodleSections.map((s) => s.name).toList();

    for (final section in config.sections) {
      final (idx, score) =
          StringMatcher.findBestMatch(section.name, moodleNames);

      MoodleSection? matched;
      if (idx >= 0) {
        matched = _moodleSections[idx];
      }

      // Atividades - fazer match interno
      final activityMatches = <ActivityMatch>[];
      if (matched != null) {
        final moduleNames = matched.modules.map((m) => m.name).toList();
        for (final activity in section.activities) {
          final (aIdx, aScore) =
              StringMatcher.findBestMatch(activity.name, moduleNames);
          activityMatches.add(ActivityMatch(
            local: activity,
            moodleModule: aIdx >= 0 ? matched.modules[aIdx] : null,
            score: aScore,
          ));
        }
      } else {
        for (final activity in section.activities) {
          activityMatches.add(ActivityMatch(
            local: activity,
            moodleModule: null,
            score: 0,
          ));
        }
      }

      _matches.add(SectionMatch(
        local: section,
        moodleSection: matched,
        score: score,
        activityMatches: activityMatches,
      ));
    }
    notifyListeners();
  }

  /// Executa a sincronização para o Moodle.
  Future<void> syncToMoodle(
      String token, String baseUrl, CourseConfig config) async {
    _syncing = true;
    _progress = 0;
    _progressMessage = 'Iniciando sincronização...';
    _error = null;
    notifyListeners();

    try {
      final totalSteps = _matches.length;
      int step = 0;

      for (final match in _matches) {
        step++;
        _progress = step / totalSteps;

        if (match.moodleSection == null) {
          _progressMessage =
              'Seção "${match.local.name}" - sem correspondência no Moodle';
          notifyListeners();
          continue;
        }

        // Atualizar nome da seção se diferente
        if (match.local.name != match.moodleSection!.name) {
          _progressMessage = 'Atualizando seção: ${match.local.name}';
          notifyListeners();
          await _repo.updateSectionName(
            token,
            baseUrl,
            match.moodleSection!.id,
            match.local.name,
          );
        }

        // Atualizar visibilidade de módulos
        for (final am in match.activityMatches) {
          if (am.moodleModule == null) continue;

          // Atualizar visibilidade se diferente
          if (am.local.visible != am.moodleModule!.visible) {
            _progressMessage = 'Visibilidade: ${am.local.name}';
            notifyListeners();
            await _repo.updateModuleVisibility(
              token,
              baseUrl,
              am.moodleModule!.id,
              am.local.visible,
            );
          }

          // Para labels: atualizar nome e conteúdo HTML
          if (am.local.activityType == 'Área de texto e mídia') {
            final htmlContent = '<p dir="ltr" style="text-align: left;"></p>'
                '<p><strong><span class="" style="color: #ef4540;"> '
                '${am.local.name} </span></strong></p>';

            _progressMessage = 'Label: ${am.local.name}';
            notifyListeners();

            await _repo.updateModuleName(
              token,
              baseUrl,
              am.moodleModule!.id,
              am.local.name,
            );

            await _repo.updateLabelContent(
              token,
              baseUrl,
              am.moodleModule!.id,
              htmlContent,
            );
          }
        }
      }

      _progressMessage = 'Sincronização concluída!';
      _progress = 1;
    } catch (e) {
      _error = 'Erro na sincronização: $e';
      _progressMessage = 'Erro!';
    }
    _syncing = false;
    notifyListeners();
  }

  void clearMatches() {
    _matches = [];
    _moodleSections = [];
    notifyListeners();
  }

  // ── Mapeamento modname → tipo local ──────────────────────────────────────

  static const _modNameMap = <String, String>{
    'assign': 'Tarefa',
    'quiz': 'Questionário',
    'survey': 'Pesquisa',
    'feedback': 'Pesquisa',
    'choice': 'Escolha',
    'forum': 'Fórum',
    'resource': 'Arquivo',
    'url': 'URL',
    'page': 'Página',
    'folder': 'Pasta',
    'wiki': 'Wiki',
    'glossary': 'Glossário',
    'lesson': 'Lição',
    'h5pactivity': 'H5P',
    'hvp': 'Conteúdo interativo',
    'data': 'Base de dados',
    'journal': 'Diário',
    'attendance': 'Presença',
    'jitsi': 'Jitsi',
    'bigbluebuttonbn': 'ConferênciaWeb',
    'book': 'Livro',
    'scorm': 'Pacote SCORM',
    'imscp': 'Conteúdo do pacote IMS',
    'simplecertificate': 'Certificado Simples',
    'checklist': 'Checklist',
    'geogebra': 'GeoGebra',
    'workshop': 'Laboratório de Avaliação',
    'label': 'Área de texto e mídia',
    'hotpot': 'Atividade Hot Potatoes',
    'quizventure': 'Quizventure',
  };

  static String _mapModName(String modname) => _modNameMap[modname] ?? modname;

  // ── Importar config a partir do Moodle ──────────────────────────────────

  /// Lê as seções e módulos do curso Moodle e constrói um [CourseConfig]
  /// com todos os IDs do Moodle já vinculados.
  Future<CourseConfig> buildConfigFromMoodle(String token, String baseUrl,
      MoodleCourse course, DateTime semesterStart) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final sections = await _repo.getCourseContents(token, baseUrl, course.id);
      final uuid = const Uuid();
      final configSections = <SectionEntry>[];
      int orderIndex = 0;

      for (final mSection in sections) {
        // Pular seção 0 "General" vazia
        if (mSection.section == 0 &&
            mSection.name.isEmpty &&
            mSection.modules.isEmpty) {
          continue;
        }

        orderIndex++;
        final activities = <ActivityEntry>[];

        for (final mod in mSection.modules) {
          // Pular labels (áreas de texto) se não tiver nome
          if (mod.name.isEmpty) continue;

          // Extrair datas do módulo (open/close)
          DateTime? openDate;
          DateTime? closeDate;
          for (final d in mod.dates) {
            final label = d.label.toLowerCase();
            if (label.contains('open') ||
                label.contains('allowsubmissionsfromdate') ||
                label.contains('timeopen') ||
                label.contains('start')) {
              if (d.timestamp > 0) openDate = d.dateTime;
            }
            if (label.contains('due') ||
                label.contains('close') ||
                label.contains('timeclose') ||
                label.contains('cutoff') ||
                label.contains('end')) {
              if (d.timestamp > 0) closeDate ??= d.dateTime;
            }
          }

          activities.add(ActivityEntry(
            id: uuid.v4(),
            name: mod.name,
            activityType: _mapModName(mod.modname),
            moodleModuleId: mod.id,
            visible: mod.visible,
            openDate: openDate,
            closeDate: closeDate,
          ));
        }

        configSections.add(SectionEntry(
          id: uuid.v4(),
          orderIndex: orderIndex,
          name: mSection.name.isNotEmpty
              ? mSection.name
              : 'Seção ${mSection.section}',
          referenceDaysOffset: 0,
          date: semesterStart,
          offsetDays: 0,
          moodleSectionId: mSection.id,
          visible: mSection.visible,
          activities: activities,
          moodleDescription:
              mSection.summary.isNotEmpty ? mSection.summary : null,
        ));
      }

      final now = DateTime.now();
      final config = CourseConfig(
        id: uuid.v4(),
        name: course.fullname,
        moodleCourseId: course.id,
        moodleCourseName: course.fullname,
        semesterStartDate: semesterStart,
        createdAt: now,
        updatedAt: now,
        sections: configSections,
      );

      _loading = false;
      notifyListeners();
      return config;
    } catch (e) {
      _loading = false;
      _error = 'Erro ao importar do Moodle: $e';
      notifyListeners();
      rethrow;
    }
  }
}

class SectionMatch {
  final SectionEntry local;
  final MoodleSection? moodleSection;
  final double score;
  final List<ActivityMatch> activityMatches;

  SectionMatch({
    required this.local,
    this.moodleSection,
    required this.score,
    this.activityMatches = const [],
  });
}

class ActivityMatch {
  final ActivityEntry local;
  final MoodleModule? moodleModule;
  final double score;

  ActivityMatch({
    required this.local,
    this.moodleModule,
    required this.score,
  });
}

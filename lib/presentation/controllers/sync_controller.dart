import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:config_moodle/core/utils/macro_resolver.dart';
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
    String token,
    String baseUrl,
    int courseId,
  ) async {
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

  /// Gera correspondências entre seções locais e seções do Moodle.
  /// Prioriza links existentes (moodleSectionId/moodleModuleId) e depois
  /// usa similaridade de nomes (Jaro-Winkler) para seções sem vínculo.
  void generateMatches(CourseConfig config) {
    _matches = [];

    // Pool de seções Moodle disponíveis (indexadas por id)
    final availableMoodleSections = {for (final s in _moodleSections) s.id: s};

    // 1ª passada: parear seções que já têm moodleSectionId vinculado
    final linkedSections = <String, MoodleSection>{}; // localId → MoodleSection
    for (final section in config.sections) {
      if (section.moodleSectionId != null &&
          availableMoodleSections.containsKey(section.moodleSectionId)) {
        linkedSections[section.id] = availableMoodleSections.remove(
          section.moodleSectionId,
        )!;
      }
    }

    // Lista de nomes restantes para match por similaridade
    final remainingMoodleSections = availableMoodleSections.values.toList();
    final remainingNames = remainingMoodleSections.map((s) => s.name).toList();

    for (final section in config.sections) {
      MoodleSection? matched;
      double score = 0;

      if (linkedSections.containsKey(section.id)) {
        // Já vinculada por moodleSectionId
        matched = linkedSections[section.id];
        score = 1.0;
      } else if (remainingNames.isNotEmpty) {
        // Match por similaridade de nome (apenas entre seções não vinculadas)
        final (idx, matchScore) = StringMatcher.findBestMatch(
          section.name,
          remainingNames,
        );
        score = matchScore;
        if (idx >= 0 && matchScore > 0.3) {
          matched = remainingMoodleSections[idx];
          // Remover do pool para evitar duplicatas
          remainingMoodleSections.removeAt(idx);
          remainingNames.removeAt(idx);
        }
      }

      // Atividades — usar vínculo existente ou match por nome
      final activityMatches = <ActivityMatch>[];
      if (matched != null) {
        // Pool de módulos disponíveis
        final availableModules = {for (final m in matched.modules) m.id: m};

        // 1ª passada: atividades com moodleModuleId vinculado
        final linkedActivities =
            <String, MoodleModule>{}; // activityId → MoodleModule
        for (final activity in section.activities) {
          if (activity.moodleModuleId != null &&
              availableModules.containsKey(activity.moodleModuleId)) {
            linkedActivities[activity.id] = availableModules.remove(
              activity.moodleModuleId,
            )!;
          }
        }

        // Nomes restantes para match por similaridade
        final remainingModules = availableModules.values.toList();
        final remainingModNames = remainingModules.map((m) => m.name).toList();

        for (final activity in section.activities) {
          if (linkedActivities.containsKey(activity.id)) {
            activityMatches.add(
              ActivityMatch(
                local: activity,
                moodleModule: linkedActivities[activity.id],
                score: 1.0,
              ),
            );
          } else if (remainingModNames.isNotEmpty) {
            final (aIdx, aScore) = StringMatcher.findBestMatch(
              activity.name,
              remainingModNames,
            );
            MoodleModule? actMatched;
            if (aIdx >= 0 && aScore > 0.3) {
              actMatched = remainingModules[aIdx];
              remainingModules.removeAt(aIdx);
              remainingModNames.removeAt(aIdx);
            }
            activityMatches.add(
              ActivityMatch(
                local: activity,
                moodleModule: actMatched,
                score: aScore,
              ),
            );
          } else {
            activityMatches.add(
              ActivityMatch(local: activity, moodleModule: null, score: 0),
            );
          }
        }
      } else {
        for (final activity in section.activities) {
          activityMatches.add(
            ActivityMatch(local: activity, moodleModule: null, score: 0),
          );
        }
      }

      _matches.add(
        SectionMatch(
          local: section,
          moodleSection: matched,
          score: score,
          activityMatches: activityMatches,
        ),
      );
    }
    notifyListeners();
  }

  /// Executa a sincronização para o Moodle.
  Future<void> syncToMoodle(
    String token,
    String baseUrl,
    CourseConfig config,
  ) async {
    _syncing = true;
    _progress = 0;
    _progressMessage = 'Iniciando sincronização...';
    _error = null;
    notifyListeners();

    final totalSteps = _matches.length;
    int step = 0;
    final errors = <String>[];
    // Flags para pular operações sem permissão após o 1º erro
    bool canUpdateNames = true;
    int skippedNameOps = 0;
    String?
    firstAccessErrorDetail; // Detalhe do 1º erro de acesso para diagnóstico

    for (final match in _matches) {
      step++;
      _progress = step / totalSteps;

      if (match.moodleSection == null) {
        _progressMessage =
            'Seção "${match.local.name}" - sem correspondência no Moodle';
        notifyListeners();
        continue;
      }

      // Data de referência para resolver macros da seção
      final sectionRefDate = config.semesterStartDate.add(
        Duration(days: match.local.referenceDaysOffset),
      );

      // Resolver macros no nome da seção antes de enviar ao Moodle
      final resolvedSectionName = MacroResolver.resolve(
        match.local.name,
        config.semesterStartDate,
        sectionRefDate,
      );

      // Atualizar nome da seção se diferente
      if (resolvedSectionName != match.moodleSection!.name) {
        if (canUpdateNames) {
          _progressMessage = 'Atualizando seção: $resolvedSectionName';
          notifyListeners();
          try {
            await _repo.updateSectionName(
              token,
              baseUrl,
              match.moodleSection!.id,
              resolvedSectionName,
            );
          } catch (e) {
            if (_isAccessError(e)) {
              canUpdateNames = false;
              firstAccessErrorDetail ??= e.toString();
              skippedNameOps++;
            } else {
              errors.add('Seção "${match.local.name}": $e');
            }
          }
        } else {
          skippedNameOps++;
        }
      }

      // Atualizar visibilidade e nomes de módulos
      for (final am in match.activityMatches) {
        if (am.moodleModule == null) continue;

        // Resolver macros no nome da atividade
        final resolvedActivityName = MacroResolver.resolve(
          am.local.name,
          config.semesterStartDate,
          sectionRefDate,
          am.local.computeOpenDate(sectionRefDate),
          am.local.computeCloseDate(sectionRefDate),
        );

        // Atualizar visibilidade se diferente
        if (am.local.visible != am.moodleModule!.visible) {
          _progressMessage = 'Visibilidade: $resolvedActivityName';
          notifyListeners();
          try {
            await _repo.updateModuleVisibility(
              token,
              baseUrl,
              am.moodleModule!.id,
              am.local.visible,
            );
          } catch (e) {
            errors.add('Visibilidade "${am.local.name}": $e');
          }
        }

        // Para labels: atualizar nome e conteúdo HTML
        if (am.local.activityType == 'Área de texto e mídia') {
          final resolvedHtml =
              '<p dir="ltr" style="text-align: left;"></p>'
              '<p><strong><span class="" style="color: #ef4540;"> '
              '$resolvedActivityName </span></strong></p>';

          if (canUpdateNames) {
            _progressMessage = 'Label: $resolvedActivityName';
            notifyListeners();
            try {
              await _repo.updateModuleName(
                token,
                baseUrl,
                am.moodleModule!.id,
                resolvedActivityName,
              );
            } catch (e) {
              if (_isAccessError(e)) {
                canUpdateNames = false;
                firstAccessErrorDetail ??= e.toString();
                skippedNameOps++;
              } else {
                errors.add('Nome label "${am.local.name}": $e');
              }
            }

            if (canUpdateNames) {
              try {
                await _repo.updateLabelContent(
                  token,
                  baseUrl,
                  am.moodleModule!.id,
                  resolvedHtml,
                );
              } catch (e) {
                if (_isAccessError(e)) {
                  canUpdateNames = false;
                  firstAccessErrorDetail ??= e.toString();
                  skippedNameOps++;
                } else {
                  errors.add('Conteúdo label "${am.local.name}": $e');
                }
              }
            } else {
              skippedNameOps++;
            }
          } else {
            skippedNameOps += 2; // nome + conteúdo
          }
        }
      }
    }

    // Construir mensagem final
    final messages = <String>[];
    if (skippedNameOps > 0) {
      final detail = firstAccessErrorDetail ?? 'Erro desconhecido';
      messages.add(
        'Atualização de nomes não disponível ($skippedNameOps operações puladas).\n\n'
        'Motivo: $detail\n\n'
        'Faça logout e login novamente para renovar a sessão.',
      );
    }
    if (errors.isNotEmpty) {
      messages.add('${errors.length} erro(s):\n${errors.join('\n')}');
    }

    if (messages.isEmpty) {
      _progressMessage = 'Sincronização concluída com sucesso!';
    } else if (errors.isEmpty && skippedNameOps > 0) {
      _progressMessage = 'Concluída (visibilidade OK, nomes ignorados)';
    } else {
      _progressMessage = 'Concluída com problemas';
    }
    _progress = 1;
    _error = messages.isNotEmpty ? messages.join('\n\n') : null;
    _syncing = false;
    notifyListeners();
  }

  /// Verifica se o erro é de controle de acesso / permissão / sessão AJAX.
  bool _isAccessError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('controle de acesso') ||
        msg.contains('access control') ||
        msg.contains('accessexception') ||
        msg.contains('not allowed') ||
        msg.contains('not available') ||
        msg.contains('não disponível') ||
        msg.contains('sessão ajax') ||
        msg.contains('sessão expirada') ||
        msg.contains('sessão foi finalizada') ||
        msg.contains('expirou') ||
        msg.contains('logintoken');
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
  Future<CourseConfig> buildConfigFromMoodle(
    String token,
    String baseUrl,
    MoodleCourse course,
    DateTime semesterStart,
  ) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final sections = await _repo.getCourseContents(token, baseUrl, course.id);
      final uuid = const Uuid();
      final configSections = <SectionEntry>[];
      int orderIndex = 0;

      // Data base normalizada (sem hora)
      final semesterStartDay = DateTime(
        semesterStart.year,
        semesterStart.month,
        semesterStart.day,
      );

      for (final mSection in sections) {
        // Pular seção 0 "General" vazia
        if (mSection.section == 0 &&
            mSection.name.isEmpty &&
            mSection.modules.isEmpty) {
          continue;
        }

        orderIndex++;
        final activities = <ActivityEntry>[];

        // Encontrar a menor data de abertura dos módulos para estimar
        // o referenceDaysOffset da seção
        DateTime? earliestOpen;

        for (final mod in mSection.modules) {
          // Pular labels (áreas de texto) se não tiver nome
          if (mod.name.isEmpty) continue;

          // Extrair datas do módulo (open/close)
          DateTime? openDate;
          DateTime? closeDate;
          for (final d in mod.dates) {
            if (d.timestamp <= 0) continue;
            if (d.isOpenDate) {
              openDate = d.dateTime;
            } else if (d.isCloseDate) {
              closeDate ??= d.dateTime;
            }
          }

          if (openDate != null) {
            if (earliestOpen == null || openDate.isBefore(earliestOpen)) {
              earliestOpen = openDate;
            }
          }

          activities.add(
            ActivityEntry(
              id: uuid.v4(),
              name: mod.name,
              activityType: _mapModName(mod.modname),
              moodleModuleId: mod.id,
              visible: mod.visible,
              openDate: openDate,
              closeDate: closeDate,
            ),
          );
        }

        // Calcular referenceDaysOffset: usar a menor data de abertura
        // como referência da seção (7 dias alinhados se possível)
        final int sectionOffset;
        if (earliestOpen != null) {
          final openDay = DateTime(
            earliestOpen.year,
            earliestOpen.month,
            earliestOpen.day,
          );
          sectionOffset = openDay.difference(semesterStartDay).inDays;
        } else {
          // Sem datas: estimar offset pela ordem (7 dias por seção)
          sectionOffset = (orderIndex - 1) * 7;
        }

        final sectionRefDate = semesterStartDay.add(
          Duration(days: sectionOffset),
        );

        // Recalcular atividades com offsets relativos à seção
        final activitiesWithOffsets = activities.map((activity) {
          int? openOffsetDays;
          int? closeOffsetDays;
          int? openTimeMinutes;
          int? closeTimeMinutes;

          if (activity.openDate != null) {
            final openDay = DateTime(
              activity.openDate!.year,
              activity.openDate!.month,
              activity.openDate!.day,
            );
            openOffsetDays = openDay.difference(sectionRefDate).inDays;
            openTimeMinutes =
                activity.openDate!.hour * 60 + activity.openDate!.minute;
          }

          if (activity.closeDate != null) {
            final closeDay = DateTime(
              activity.closeDate!.year,
              activity.closeDate!.month,
              activity.closeDate!.day,
            );
            closeOffsetDays = closeDay.difference(sectionRefDate).inDays;
            closeTimeMinutes =
                activity.closeDate!.hour * 60 + activity.closeDate!.minute;
          }

          return activity.copyWith(
            openOffsetDays: openOffsetDays,
            closeOffsetDays: closeOffsetDays,
            openTimeMinutes: openTimeMinutes,
            closeTimeMinutes: closeTimeMinutes,
          );
        }).toList();

        configSections.add(
          SectionEntry(
            id: uuid.v4(),
            orderIndex: orderIndex,
            name: mSection.name.isNotEmpty
                ? mSection.name
                : 'Seção ${mSection.section}',
            referenceDaysOffset: sectionOffset,
            date: sectionRefDate,
            offsetDays: sectionOffset,
            moodleSectionId: mSection.id,
            visible: mSection.visible,
            activities: activitiesWithOffsets,
            moodleDescription: mSection.summary.isNotEmpty
                ? mSection.summary
                : null,
          ),
        );
      }

      // ── Substituir datas hardcoded por macros nos textos ──────────────────
      for (int i = 0; i < configSections.length; i++) {
        final section = configSections[i];
        final sectionRefDate = semesterStartDay.add(
          Duration(days: section.referenceDaysOffset),
        );

        final newName = MacroResolver.replaceDatesWithMacros(
          section.name,
          sectionRefDate,
        );
        final newDesc = section.moodleDescription != null
            ? MacroResolver.replaceDatesWithMacros(
                section.moodleDescription!,
                sectionRefDate,
              )
            : null;

        final updatedActivities = section.activities.map((activity) {
          final openDate = activity.computeOpenDate(sectionRefDate);
          final closeDate = activity.computeCloseDate(sectionRefDate);
          final newActName = MacroResolver.replaceDatesWithMacros(
            activity.name,
            sectionRefDate,
            activityOpenDate: openDate,
            activityCloseDate: closeDate,
          );
          return newActName != activity.name
              ? activity.copyWith(name: newActName)
              : activity;
        }).toList();

        configSections[i] = section.copyWith(
          name: newName,
          moodleDescription: newDesc,
          activities: updatedActivities,
        );
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

  ActivityMatch({required this.local, this.moodleModule, required this.score});
}

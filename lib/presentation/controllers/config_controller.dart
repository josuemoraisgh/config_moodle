import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:config_moodle/core/utils/date_calculator.dart';
import 'package:config_moodle/domain/entities/course_config.dart';
import 'package:config_moodle/domain/repositories/i_config_repository.dart';

class ConfigController extends ChangeNotifier {
  final IConfigRepository _repo;
  final _uuid = const Uuid();

  ConfigController(this._repo);

  List<CourseConfig> _configs = [];
  CourseConfig? _current;
  bool _loading = false;
  String? _error;
  final Set<String> _selectedActivityIds = {};

  List<CourseConfig> get configs => _configs;
  CourseConfig? get current => _current;
  bool get loading => _loading;
  String? get error => _error;
  Set<String> get selectedActivityIds => _selectedActivityIds;
  bool get hasSelection => _selectedActivityIds.isNotEmpty;

  Future<void> loadAll() async {
    _loading = true;
    notifyListeners();
    try {
      _configs = await _repo.getAll();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadById(String id) async {
    _loading = true;
    notifyListeners();
    try {
      _current = await _repo.getById(id);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> createEmpty(String name) async {
    final now = DateTime.now();
    final config = CourseConfig(
      id: _uuid.v4(),
      name: name,
      semesterStartDate: now,
      createdAt: now,
      updatedAt: now,
      sections: [],
    );
    await _repo.save(config);
    await loadAll();
  }

  Future<void> saveNewConfig(CourseConfig config) async {
    await _repo.save(config);
    await loadAll();
  }

  Future<void> importSpreadsheet(String filePath, {String? replaceId}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.importFromSpreadsheet(filePath, replaceId: replaceId);
      await loadAll();
    } catch (e) {
      _error = 'Erro ao importar: $e';
    }
    _loading = false;
    notifyListeners();
  }

  /// Retorna configs existentes cujo nome coincide com alguma sheet da planilha.
  List<CourseConfig> findDuplicates(String filePath) {
    final repo = _repo as dynamic;
    final parsed = repo.parseSpreadsheet(filePath) as List<CourseConfig>;
    if (parsed.isEmpty) return [];
    final names = parsed.map((c) => c.name.toLowerCase()).toSet();
    return _configs.where((c) => names.contains(c.name.toLowerCase())).toList();
  }

  Future<Uint8List?> exportSpreadsheetBytes(String courseConfigId) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final bytes = await _repo.exportToSpreadsheetBytes(courseConfigId);
      _loading = false;
      notifyListeners();
      return bytes;
    } catch (e) {
      _error = 'Erro ao exportar: $e';
      _loading = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteConfig(String id) async {
    await _repo.delete(id);
    if (_current?.id == id) _current = null;
    await loadAll();
  }

  // ── Edição de data principal ──────────────────────────────────────────────

  Future<void> updateSemesterStartDate(DateTime newDate) async {
    if (_current == null) return;

    final oldDate = _current!.semesterStartDate;
    final offsetShift = newDate.difference(oldDate).inDays;

    final updatedSections = _current!.sections.map((section) {
      final newSectionDate = section.date.add(Duration(days: offsetShift));
      final sectionRefDate =
          newDate.add(Duration(days: section.referenceDaysOffset));
      final updatedActivities = section.activities.map((activity) {
        // Recomputar datas absolutas a partir dos offsets
        return activity.copyWith(
          openDate: activity.computeOpenDate(sectionRefDate),
          closeDate: activity.computeCloseDate(sectionRefDate),
        );
      }).toList();
      return section.copyWith(
        date: newSectionDate,
        activities: updatedActivities,
      );
    }).toList();

    _current = _current!.copyWith(
      semesterStartDate: newDate,
      sections: updatedSections,
    );
    await _repo.save(_current!);
    notifyListeners();
  }

  // ── CRUD Seções ───────────────────────────────────────────────────────────

  Future<void> addSection(String name, DateTime date) async {
    if (_current == null) return;
    final offset =
        DateCalculator.calculateOffset(_current!.semesterStartDate, date);
    final section = SectionEntry(
      id: _uuid.v4(),
      orderIndex: _current!.sections.length + 1,
      name: name,
      referenceDaysOffset: offset,
      date: date,
      offsetDays: offset,
    );
    _current = _current!.copyWith(
      sections: [..._current!.sections, section],
    );
    await _repo.save(_current!);
    notifyListeners();
  }

  Future<void> updateSection(String sectionId,
      {String? name,
      int? referenceDaysOffset,
      DateTime? date,
      bool? visible}) async {
    if (_current == null) return;
    final sections = _current!.sections.map((s) {
      if (s.id != sectionId) return s;
      final newRefOffset = referenceDaysOffset ?? s.referenceDaysOffset;
      final newDate =
          date ?? _current!.semesterStartDate.add(Duration(days: newRefOffset));
      final newOffsetDays =
          DateCalculator.calculateOffset(_current!.semesterStartDate, newDate);
      return s.copyWith(
        name: name,
        referenceDaysOffset: newRefOffset,
        date: newDate,
        offsetDays: newOffsetDays,
        visible: visible,
      );
    }).toList();
    _current = _current!.copyWith(sections: sections);
    await _repo.save(_current!);
    notifyListeners();
  }

  Future<void> removeSection(String sectionId) async {
    if (_current == null) return;
    final sections =
        _current!.sections.where((s) => s.id != sectionId).toList();
    _current = _current!.copyWith(sections: sections);
    await _repo.save(_current!);
    notifyListeners();
  }

  // ── CRUD Atividades ───────────────────────────────────────────────────────

  Future<void> addActivity(String sectionId, String name, String type,
      {int? openOffsetDays,
      int? closeOffsetDays,
      int? openTimeMinutes,
      int? closeTimeMinutes,
      int? moodleModuleId}) async {
    if (_current == null) return;
    final section = _current!.sections.firstWhere((s) => s.id == sectionId);
    final sectionRefDate = _current!.semesterStartDate
        .add(Duration(days: section.referenceDaysOffset));
    final activity = ActivityEntry(
      id: _uuid.v4(),
      name: name,
      activityType: type,
      moodleModuleId: moodleModuleId,
      openOffsetDays: openOffsetDays,
      closeOffsetDays: closeOffsetDays,
      openTimeMinutes: openTimeMinutes,
      closeTimeMinutes: closeTimeMinutes,
    );
    // Computar datas absolutas para export/compat
    final withDates = activity.copyWith(
      openDate: activity.computeOpenDate(sectionRefDate),
      closeDate: activity.computeCloseDate(sectionRefDate),
    );
    final sections = _current!.sections.map((s) {
      if (s.id != sectionId) return s;
      return s.copyWith(activities: [...s.activities, withDates]);
    }).toList();
    _current = _current!.copyWith(sections: sections);
    await _repo.save(_current!);
    notifyListeners();
  }

  static const _sentinel = Object();

  Future<void> updateActivity(String sectionId, String activityId,
      {String? name,
      String? type,
      Object? openOffsetDays = _sentinel,
      Object? closeOffsetDays = _sentinel,
      Object? openTimeMinutes = _sentinel,
      Object? closeTimeMinutes = _sentinel,
      Object? moodleModuleId = _sentinel,
      bool? visible}) async {
    if (_current == null) return;
    final sections = _current!.sections.map((s) {
      if (s.id != sectionId) return s;
      final sectionRefDate = _current!.semesterStartDate
          .add(Duration(days: s.referenceDaysOffset));
      final activities = s.activities.map((a) {
        if (a.id != activityId) return a;
        final updated = a.copyWith(
          name: name,
          activityType: type,
          openOffsetDays: openOffsetDays == _sentinel
              ? a.openOffsetDays
              : openOffsetDays as int?,
          closeOffsetDays: closeOffsetDays == _sentinel
              ? a.closeOffsetDays
              : closeOffsetDays as int?,
          openTimeMinutes: openTimeMinutes == _sentinel
              ? a.openTimeMinutes
              : openTimeMinutes as int?,
          closeTimeMinutes: closeTimeMinutes == _sentinel
              ? a.closeTimeMinutes
              : closeTimeMinutes as int?,
          moodleModuleId: moodleModuleId == _sentinel
              ? a.moodleModuleId
              : moodleModuleId as int?,
          visible: visible,
        );
        // Recomputar datas absolutas
        return updated.copyWith(
          openDate: updated.computeOpenDate(sectionRefDate),
          closeDate: updated.computeCloseDate(sectionRefDate),
        );
      }).toList();
      return s.copyWith(activities: activities);
    }).toList();
    _current = _current!.copyWith(sections: sections);
    await _repo.save(_current!);
    notifyListeners();
  }

  Future<void> removeActivity(String sectionId, String activityId) async {
    if (_current == null) return;
    final sections = _current!.sections.map((s) {
      if (s.id != sectionId) return s;
      return s.copyWith(
        activities: s.activities.where((a) => a.id != activityId).toList(),
      );
    }).toList();
    _current = _current!.copyWith(sections: sections);
    await _repo.save(_current!);
    notifyListeners();
  }

  Future<void> reorderActivities(
      String sectionId, int oldIndex, int newIndex) async {
    if (_current == null) return;

    if (_selectedActivityIds.isNotEmpty) {
      await _reorderSelectedActivities(sectionId, oldIndex, newIndex);
      return;
    }

    final sections = _current!.sections.map((s) {
      if (s.id != sectionId) return s;
      final list = [...s.activities];
      final item = list.removeAt(oldIndex);
      if (newIndex > oldIndex) newIndex--;
      list.insert(newIndex, item);
      return s.copyWith(activities: list);
    }).toList();
    _current = _current!.copyWith(sections: sections);
    await _repo.save(_current!);
    notifyListeners();
  }

  Future<void> _reorderSelectedActivities(
      String sectionId, int draggedIndex, int targetIndex) async {
    if (_current == null) return;

    // ReorderableListView convention: adjust targetIndex when moving down
    if (targetIndex > draggedIndex) targetIndex--;

    final sections = _current!.sections.map((s) {
      if (s.id != sectionId) return s;
      final activities = [...s.activities];
      final selectedIds = _selectedActivityIds;

      // Ensure dragged item is in selection
      final draggedId = activities[draggedIndex].id;
      if (!selectedIds.contains(draggedId)) {
        // Fallback to single-item reorder
        final item = activities.removeAt(draggedIndex);
        activities.insert(targetIndex, item);
        return s.copyWith(activities: activities);
      }

      // Extract selected items preserving their relative order
      final selected =
          activities.where((a) => selectedIds.contains(a.id)).toList();
      final remaining =
          activities.where((a) => !selectedIds.contains(a.id)).toList();

      // Compute insertion index in the remaining list:
      // Count how many non-selected items are before the target position
      final insertAt = activities
          .sublist(0, targetIndex + (targetIndex >= draggedIndex ? 1 : 0))
          .where((a) => !selectedIds.contains(a.id))
          .length
          .clamp(0, remaining.length);

      remaining.insertAll(insertAt, selected);
      return s.copyWith(activities: remaining);
    }).toList();
    _current = _current!.copyWith(sections: sections);
    _selectedActivityIds.clear();
    await _repo.save(_current!);
    notifyListeners();
  }

  Future<void> moveActivity(
      String fromSectionId, String toSectionId, String activityId) async {
    if (_current == null) return;
    ActivityEntry? moving;
    var sections = _current!.sections.map((s) {
      if (s.id != fromSectionId) return s;
      moving = s.activities.firstWhere((a) => a.id == activityId);
      return s.copyWith(
        activities: s.activities.where((a) => a.id != activityId).toList(),
      );
    }).toList();
    if (moving == null) return;
    sections = sections.map((s) {
      if (s.id != toSectionId) return s;
      return s.copyWith(activities: [...s.activities, moving!]);
    }).toList();
    _current = _current!.copyWith(sections: sections);
    await _repo.save(_current!);
    notifyListeners();
  }

  void toggleActivitySelection(String activityId) {
    if (_selectedActivityIds.contains(activityId)) {
      _selectedActivityIds.remove(activityId);
    } else {
      _selectedActivityIds.add(activityId);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedActivityIds.clear();
    notifyListeners();
  }

  Future<void> moveSelectedActivities(String toSectionId) async {
    if (_current == null || _selectedActivityIds.isEmpty) return;
    final ids = Set<String>.from(_selectedActivityIds);
    final List<ActivityEntry> moving = [];

    var sections = _current!.sections.map((s) {
      final toMove = s.activities.where((a) => ids.contains(a.id)).toList();
      if (toMove.isEmpty) return s;
      moving.addAll(toMove);
      return s.copyWith(
        activities: s.activities.where((a) => !ids.contains(a.id)).toList(),
      );
    }).toList();

    if (moving.isEmpty) return;

    sections = sections.map((s) {
      if (s.id != toSectionId) return s;
      return s.copyWith(activities: [...s.activities, ...moving]);
    }).toList();

    _current = _current!.copyWith(sections: sections);
    _selectedActivityIds.clear();
    await _repo.save(_current!);
    notifyListeners();
  }

  /// Move selected activities to [toSectionId] inserting at [insertIndex].
  /// Used for within-section reorder via drag-and-drop.
  Future<void> moveSelectedActivitiesAtIndex(
      String toSectionId, int insertIndex) async {
    if (_current == null || _selectedActivityIds.isEmpty) return;
    final ids = Set<String>.from(_selectedActivityIds);
    final List<ActivityEntry> moving = [];

    var sections = _current!.sections.map((s) {
      final toMove = s.activities.where((a) => ids.contains(a.id)).toList();
      if (toMove.isEmpty) return s;
      moving.addAll(toMove);
      return s.copyWith(
        activities: s.activities.where((a) => !ids.contains(a.id)).toList(),
      );
    }).toList();

    if (moving.isEmpty) return;

    sections = sections.map((s) {
      if (s.id != toSectionId) return s;
      final list = [...s.activities];
      final clampedIdx = insertIndex.clamp(0, list.length);
      list.insertAll(clampedIdx, moving);
      return s.copyWith(activities: list);
    }).toList();

    _current = _current!.copyWith(sections: sections);
    _selectedActivityIds.clear();
    await _repo.save(_current!);
    notifyListeners();
  }

  Future<void> updateConfigName(String name) async {
    if (_current == null) return;
    _current = _current!.copyWith(name: name);
    await _repo.save(_current!);
    notifyListeners();
  }

  Future<void> linkMoodleCourse(
      int moodleCourseId, String moodleCourseName) async {
    if (_current == null) return;
    _current = _current!.copyWith(
      moodleCourseId: moodleCourseId,
      moodleCourseName: moodleCourseName,
    );
    await _repo.save(_current!);
    notifyListeners();
  }

  Future<void> linkSectionToMoodle(
      String sectionId, int? moodleSectionId) async {
    if (_current == null) return;
    final sections = _current!.sections.map((s) {
      if (s.id != sectionId) return s;
      return s.copyWith(moodleSectionId: moodleSectionId);
    }).toList();
    _current = _current!.copyWith(sections: sections);
    await _repo.save(_current!);
    notifyListeners();
  }

  Future<void> linkActivityToMoodle(
      String sectionId, String activityId, int? moodleModuleId) async {
    if (_current == null) return;
    final sections = _current!.sections.map((s) {
      if (s.id != sectionId) return s;
      final activities = s.activities.map((a) {
        if (a.id != activityId) return a;
        return a.copyWith(moodleModuleId: moodleModuleId);
      }).toList();
      return s.copyWith(activities: activities);
    }).toList();
    _current = _current!.copyWith(sections: sections);
    await _repo.save(_current!);
    notifyListeners();
  }
}

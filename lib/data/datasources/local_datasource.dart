import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:config_moodle/domain/entities/course_config.dart';

class LocalDatasource {
  static const _storageKey = 'config_moodle_data';
  Map<String, CourseConfig>? _cache;

  Future<Map<String, CourseConfig>> _loadAll() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _cache = {};
      return _cache!;
    }
    final Map<String, dynamic> jsonMap =
        json.decode(raw) as Map<String, dynamic>;
    _cache = jsonMap.map(
      (k, v) => MapEntry(k, CourseConfig.fromJson(v as Map<String, dynamic>)),
    );
    return _cache!;
  }

  Future<void> _saveAll() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonMap = _cache!.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_storageKey, json.encode(jsonMap));
  }

  Future<List<CourseConfig>> getAll() async {
    final map = await _loadAll();
    return map.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<CourseConfig?> getById(String id) async {
    final map = await _loadAll();
    return map[id];
  }

  Future<void> save(CourseConfig config) async {
    await _loadAll();
    _cache![config.id] = config;
    await _saveAll();
  }

  Future<void> delete(String id) async {
    await _loadAll();
    _cache!.remove(id);
    await _saveAll();
  }
}

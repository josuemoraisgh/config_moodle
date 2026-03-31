import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:config_moodle/domain/entities/course_config.dart';

class LocalDatasource {
  static const _fileName = 'config_moodle_data.json';
  Map<String, CourseConfig>? _cache;

  Future<String> get _filePath async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _fileName);
  }

  Future<Map<String, CourseConfig>> _loadAll() async {
    if (_cache != null) return _cache!;
    final path = await _filePath;
    final file = File(path);
    if (!await file.exists()) {
      _cache = {};
      return _cache!;
    }
    final content = await file.readAsString();
    final Map<String, dynamic> jsonMap =
        json.decode(content) as Map<String, dynamic>;
    _cache = jsonMap.map((k, v) =>
        MapEntry(k, CourseConfig.fromJson(v as Map<String, dynamic>)));
    return _cache!;
  }

  Future<void> _saveAll() async {
    final path = await _filePath;
    final file = File(path);
    final jsonMap = _cache!.map((k, v) => MapEntry(k, v.toJson()));
    await file.writeAsString(json.encode(jsonMap));
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

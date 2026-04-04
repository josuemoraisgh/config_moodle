import 'dart:typed_data';
import 'package:config_moodle/domain/entities/course_config.dart';

abstract class IConfigRepository {
  Future<List<CourseConfig>> getAll();
  Future<CourseConfig?> getById(String id);
  Future<void> save(CourseConfig config);
  Future<void> delete(String id);
  Future<CourseConfig> importFromSpreadsheet(
    String filePath, {
    String? replaceId,
  });
  Future<CourseConfig> importFromSpreadsheetBytes(
    Uint8List bytes, {
    String? replaceId,
  });
  Future<Uint8List> exportToSpreadsheetBytes(String courseConfigId);
  List<CourseConfig> parseSpreadsheetBytes(Uint8List bytes);
}

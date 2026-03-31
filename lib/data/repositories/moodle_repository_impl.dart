import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:config_moodle/data/datasources/moodle_datasource.dart';
import 'package:config_moodle/domain/entities/moodle_entities.dart';
import 'package:config_moodle/domain/repositories/i_moodle_repository.dart';

class MoodleRepositoryImpl implements IMoodleRepository {
  final MoodleDatasource _datasource;
  static const _credKey = 'moodle_credential';

  MoodleRepositoryImpl(this._datasource);

  @override
  Future<MoodleCredential> login(
      String baseUrl, String username, String password) async {
    return _datasource.login(baseUrl, username, password);
  }

  @override
  Future<MoodleCredential?> getSavedCredential() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_credKey);
    if (raw == null) return null;
    return MoodleCredential.fromJson(json.decode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> saveCredential(MoodleCredential credential) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_credKey, json.encode(credential.toJson()));
  }

  @override
  Future<void> clearCredential() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_credKey);
  }

  @override
  Future<List<MoodleCourse>> getCourses(String token, String baseUrl) async {
    final cred = await getSavedCredential();
    if (cred == null) throw Exception('Usuário não autenticado');
    return _datasource.getCourses(token, baseUrl, cred.userId);
  }

  @override
  Future<List<MoodleSection>> getCourseContents(
      String token, String baseUrl, int courseId) async {
    return _datasource.getCourseContents(token, baseUrl, courseId);
  }

  @override
  Future<void> updateSectionName(
      String token, String baseUrl, int sectionId, String newName) async {
    return _datasource.updateSectionName(token, baseUrl, sectionId, newName);
  }

  @override
  Future<void> updateModuleVisibility(
      String token, String baseUrl, int moduleId, bool visible) async {
    return _datasource.updateModuleVisibility(
        token, baseUrl, moduleId, visible);
  }

  @override
  Future<void> updateModuleName(
      String token, String baseUrl, int moduleId, String newName) async {
    return _datasource.updateModuleName(token, baseUrl, moduleId, newName);
  }

  @override
  Future<void> updateLabelContent(
      String token, String baseUrl, int moduleId, String htmlContent) async {
    return _datasource.updateLabelContent(
        token, baseUrl, moduleId, htmlContent);
  }
}

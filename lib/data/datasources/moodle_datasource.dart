import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:config_moodle/domain/entities/moodle_entities.dart';

class MoodleDatasource {
  Future<Map<String, dynamic>> _callWs(
    String baseUrl,
    String token,
    String function, {
    Map<String, String> params = const {},
  }) async {
    final uri = Uri.parse('$baseUrl/webservice/rest/server.php').replace(
      queryParameters: {
        'wstoken': token,
        'wsfunction': function,
        'moodlewsrestformat': 'json',
        ...params,
      },
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw MoodleException('HTTP ${response.statusCode}');
    }
    final body = json.decode(response.body);
    if (body is Map && body.containsKey('exception')) {
      throw MoodleException(body['message'] ?? body['exception']);
    }
    return {'data': body};
  }

  Future<MoodleCredential> login(
      String baseUrl, String username, String password) async {
    final uri = Uri.parse('$baseUrl/login/token.php');
    final response = await http.post(uri, body: {
      'username': username,
      'password': password,
      'service': 'moodle_mobile_app',
    });

    if (response.statusCode != 200) {
      throw MoodleException('Falha na conexão com o Moodle');
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    if (body.containsKey('error')) {
      throw MoodleException(body['error'] as String);
    }

    final token = body['token'] as String;

    // Get user info
    final info = await _callWs(baseUrl, token, 'core_webservice_get_site_info');
    final data = info['data'] as Map<String, dynamic>;

    return MoodleCredential(
      moodleUrl: baseUrl,
      username: username,
      token: token,
      userId: data['userid'] as int,
      fullname: data['fullname'] as String? ?? username,
      savedAt: DateTime.now(),
    );
  }

  Future<List<MoodleCourse>> getCourses(
      String token, String baseUrl, int userId) async {
    final result = await _callWs(
      baseUrl,
      token,
      'core_enrol_get_users_courses',
      params: {'userid': userId.toString()},
    );
    final list = result['data'] as List;
    return list
        .map((c) => MoodleCourse.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<List<MoodleSection>> getCourseContents(
      String token, String baseUrl, int courseId) async {
    final result = await _callWs(
      baseUrl,
      token,
      'core_course_get_contents',
      params: {'courseid': courseId.toString()},
    );
    final list = result['data'] as List;
    return list
        .map((s) => MoodleSection.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateSectionName(
      String token, String baseUrl, int sectionId, String newName) async {
    await _callWs(
      baseUrl,
      token,
      'core_update_inplace_editable',
      params: {
        'component': 'core_course',
        'itemtype': 'sectionname',
        'itemid': sectionId.toString(),
        'value': newName,
      },
    );
  }

  Future<void> updateModuleVisibility(
      String token, String baseUrl, int moduleId, bool visible) async {
    await _callWs(
      baseUrl,
      token,
      'core_course_edit_module',
      params: {
        'id': moduleId.toString(),
        'action': visible ? 'show' : 'hide',
      },
    );
  }

  Future<void> updateModuleName(
      String token, String baseUrl, int moduleId, String newName) async {
    await _callWs(
      baseUrl,
      token,
      'core_update_inplace_editable',
      params: {
        'component': 'core_course',
        'itemtype': 'activityname',
        'itemid': moduleId.toString(),
        'value': newName,
      },
    );
  }

  Future<void> updateLabelContent(
      String token, String baseUrl, int moduleId, String htmlContent) async {
    await _callWs(
      baseUrl,
      token,
      'core_update_inplace_editable',
      params: {
        'component': 'mod_label',
        'itemtype': 'content',
        'itemid': moduleId.toString(),
        'value': htmlContent,
      },
    );
  }
}

class MoodleException implements Exception {
  final String message;
  MoodleException(this.message);
  @override
  String toString() => 'MoodleException: $message';
}

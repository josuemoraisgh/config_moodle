import 'dart:convert';
import 'dart:io' as io;
import 'package:http/http.dart' as http;
import 'package:config_moodle/domain/entities/moodle_entities.dart';

class MoodleDatasource {
  // ── Sessão web para chamadas AJAX ──────────────────────────────────────
  // Funções como core_update_inplace_editable são marcadas como 'ajax'
  // no Moodle e NÃO estão em nenhum serviço web externo por padrão.
  // Usando login via formulário HTML, obtemos um cookie de sessão e uma
  // sesskey que permitem chamar essas funções via /lib/ajax/service.php.
  String? _sessionCookie;
  String? _sesskey;
  String? _sessionError; // Motivo da falha para diagnóstico

  Future<Map<String, dynamic>> _callWs(
    String baseUrl,
    String token,
    String function, {
    Map<String, String> params = const {},
    bool usePost = false,
  }) async {
    final baseParams = {
      'wstoken': token,
      'wsfunction': function,
      'moodlewsrestformat': 'json',
    };

    late final http.Response response;
    if (usePost) {
      final uri = Uri.parse('$baseUrl/webservice/rest/server.php');
      response = await http.post(uri, body: {...baseParams, ...params});
    } else {
      final uri = Uri.parse(
        '$baseUrl/webservice/rest/server.php',
      ).replace(queryParameters: {...baseParams, ...params});
      response = await http.get(uri);
    }
    if (response.statusCode != 200) {
      throw MoodleException('HTTP ${response.statusCode}');
    }
    final body = json.decode(response.body);
    if (body is Map && body.containsKey('exception')) {
      throw MoodleException(body['message'] ?? body['exception']);
    }
    return {'data': body};
  }

  /// Serviços externos tentados na ordem: primeiro um serviço personalizado
  /// com permissões de escrita, depois o serviço mobile padrão.
  static const _services = [
    'config_moodle_service', // Serviço externo criado pelo admin com funções de edição
    'moodle_mobile_app', // Serviço padrão (somente leitura em muitos Moodles)
  ];

  /// Indica se a sessão AJAX foi estabelecida com sucesso.
  bool get hasAjaxSession => _sessionCookie != null && _sesskey != null;

  /// Motivo da falha na sessão AJAX (null se sucesso).
  String? get sessionError => _sessionError;

  /// Extrai a sesskey embutida no HTML de uma página Moodle.
  String? _findSesskey(String body) {
    // "sesskey":"abc123" (em blocos JS)
    var match = RegExp(r'"sesskey"\s*:\s*"([^"]+)"').firstMatch(body);
    // name="sesskey" value="abc123" (hidden fields)
    match ??= RegExp(r'name="sesskey"[^>]*value="([^"]+)"').firstMatch(body);
    // value="abc123" name="sesskey" (ordem invertida)
    match ??= RegExp(r'value="([^"]+)"[^>]*name="sesskey"').firstMatch(body);
    return match?.group(1);
  }

  /// Estabelece sessão web via formulário de login HTML do Moodle.
  /// Usa dart:io HttpClient para controle confiável de cookies e redirects.
  Future<void> _establishSession(
    String baseUrl,
    String username,
    String password,
  ) async {
    _sessionCookie = null;
    _sesskey = null;
    _sessionError = null;

    final client = io.HttpClient();
    // Aceitar certificados autoassinados (comum em servidores Moodle)
    client.badCertificateCallback = (cert, host, port) => true;
    try {
      // 1. GET na página de login para obter o logintoken (CSRF)
      final getReq = await client.getUrl(Uri.parse('$baseUrl/login/index.php'));
      final getResp = await getReq.close();
      final loginHtml = await getResp.transform(utf8.decoder).join();

      // Aceitar múltiplos formatos do campo logintoken
      final tokenMatch = RegExp(
        r'name="logintoken"[^>]*value="([^"]+)"',
      ).firstMatch(loginHtml);
      // Tentar formato invertido: value="..." name="logintoken"
      final token =
          tokenMatch?.group(1) ??
          RegExp(
            r'value="([^"]+)"[^>]*name="logintoken"',
          ).firstMatch(loginHtml)?.group(1);

      if (token == null) {
        _sessionError = 'logintoken não encontrado na página de login';
        return;
      }

      // 2. POST no formulário de login (sem seguir redirect)
      final postReq = await client.postUrl(
        Uri.parse('$baseUrl/login/index.php'),
      );
      postReq.followRedirects = false;
      postReq.headers.contentType = io.ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      final formBody = Uri(
        queryParameters: {
          'username': username,
          'password': password,
          'logintoken': token,
        },
      ).query;
      postReq.write(formBody);
      final postResp = await postReq.close();
      await postResp.drain<void>();

      // Extrair MoodleSession do Set-Cookie da resposta 303
      for (final cookie in postResp.cookies) {
        if (cookie.name == 'MoodleSession') {
          _sessionCookie = cookie.value;
        }
      }
      // Fallback: parsear Set-Cookie raw (cookies mal-formados falham no parser)
      if (_sessionCookie == null) {
        final rawCookies = postResp.headers['set-cookie'];
        if (rawCookies != null) {
          for (final raw in rawCookies) {
            final match = RegExp(r'MoodleSession=([^;]+)').firstMatch(raw);
            if (match != null) {
              _sessionCookie = match.group(1);
            }
          }
        }
      }

      if (_sessionCookie == null) {
        // Login pode ter retornado 200 (erro) em vez de 303 (redirect)
        _sessionError =
            'Cookie de sessão não recebido (HTTP ${postResp.statusCode}). '
            'Login via formulário pode não ser suportado.';
        return;
      }

      // 3. Seguir redirect manualmente para extrair a sesskey
      // O cookie é gerenciado automaticamente pelo dart:io HttpClient
      final location = postResp.headers.value('location');
      final targetUrl = (location != null && location.startsWith('http'))
          ? location
          : '$baseUrl${location ?? '/my/'}';

      final pageReq = await client.getUrl(Uri.parse(targetUrl));
      final pageResp = await pageReq.close();
      final dashHtml = await pageResp.transform(utf8.decoder).join();

      // Atualizar cookie se o servidor renovou na página de destino
      for (final cookie in pageResp.cookies) {
        if (cookie.name == 'MoodleSession') {
          _sessionCookie = cookie.value;
        }
      }

      _sesskey = _findSesskey(dashHtml);
      if (_sesskey == null) {
        _sessionError = 'sesskey não encontrada no HTML (página: $targetUrl)';
        _sessionCookie = null; // Invalidar sessão incompleta
        return;
      }
      // Sessão AJAX estabelecida com sucesso (cookie + sesskey presentes)
    } catch (e) {
      _sessionError = 'Erro ao estabelecer sessão: $e';
      _sessionCookie = null;
      _sesskey = null;
    } finally {
      client.close();
    }
  }

  /// Chama uma função AJAX do Moodle usando sessão web.
  /// Funciona para funções marcadas 'ajax' => true no Moodle, mesmo que
  /// NÃO estejam em nenhum serviço web externo (ex: core_update_inplace_editable).
  Future<Map<String, dynamic>> _callAjax(
    String baseUrl,
    String function,
    Map<String, String> args,
  ) async {
    if (!hasAjaxSession) {
      throw MoodleException(_sessionError ?? 'Sessão AJAX não estabelecida');
    }

    // Usar dart:io HttpClient para garantir envio correto do cookie
    final client = io.HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    try {
      final uri = Uri.parse(
        '$baseUrl/lib/ajax/service.php'
        '?sesskey=$_sesskey&info=$function',
      );

      final request = await client.postUrl(uri);
      request.headers.contentType = io.ContentType.json;
      request.headers.set('Cookie', 'MoodleSession=$_sessionCookie');
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.write(
        json.encode([
          {'index': 0, 'methodname': function, 'args': args},
        ]),
      );

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      // Atualizar cookie se renovado
      for (final cookie in response.cookies) {
        if (cookie.name == 'MoodleSession') {
          _sessionCookie = cookie.value;
        }
      }

      if (response.statusCode != 200) {
        throw MoodleException('AJAX HTTP ${response.statusCode}');
      }

      try {
        final decoded = json.decode(body);
        if (decoded is List && decoded.isNotEmpty) {
          final result = decoded[0] as Map<String, dynamic>;
          if (result['error'] == true) {
            final ex = result['exception'] as Map<String, dynamic>?;
            throw MoodleException(
              ex?['message'] as String? ?? 'Erro AJAX desconhecido',
            );
          }
          return {'data': result['data']};
        }
      } on FormatException {
        // Resposta não é JSON — sessão expirou e Moodle retornou HTML de login
        _sessionCookie = null;
        _sesskey = null;
        _sessionError = 'Sessão expirada';
      }
      throw MoodleException('Sessão AJAX expirada — faça login novamente');
    } finally {
      client.close();
    }
  }

  Future<MoodleCredential> login(
    String baseUrl,
    String username,
    String password,
  ) async {
    String? token;
    String? lastError;

    for (final service in _services) {
      final uri = Uri.parse('$baseUrl/login/token.php');
      final response = await http.post(
        uri,
        body: {'username': username, 'password': password, 'service': service},
      );

      if (response.statusCode != 200) continue;

      final body = json.decode(response.body) as Map<String, dynamic>;
      if (body.containsKey('error')) {
        lastError = body['error'] as String;
        continue;
      }

      token = body['token'] as String;
      break;
    }

    if (token == null) {
      throw MoodleException(lastError ?? 'Falha na conexão com o Moodle');
    }

    // Estabelecer sessão web para chamadas AJAX (renomear seções/módulos)
    await _establishSession(baseUrl, username, password);

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
    String token,
    String baseUrl,
    int userId,
  ) async {
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
    String token,
    String baseUrl,
    int courseId,
  ) async {
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
    String token,
    String baseUrl,
    int sectionId,
    String newName,
  ) async {
    final params = {
      'component': 'core_course',
      'itemtype': 'sectionname',
      'itemid': sectionId.toString(),
      'value': newName,
    };
    // Tentar AJAX primeiro (funciona sem configuração do admin)
    if (hasAjaxSession) {
      await _callAjax(baseUrl, 'core_update_inplace_editable', params);
      return;
    }
    // Fallback para WS token (requer configuração do admin)
    try {
      await _callWs(
        baseUrl,
        token,
        'core_update_inplace_editable',
        usePost: true,
        params: params,
      );
    } catch (wsError) {
      throw MoodleException(
        'Sessão AJAX: ${_sessionError ?? "não disponível"}. '
        'WS: $wsError',
      );
    }
  }

  Future<void> updateModuleVisibility(
    String token,
    String baseUrl,
    int moduleId,
    bool visible,
  ) async {
    await _callWs(
      baseUrl,
      token,
      'core_course_edit_module',
      usePost: true,
      params: {'id': moduleId.toString(), 'action': visible ? 'show' : 'hide'},
    );
  }

  Future<void> updateModuleName(
    String token,
    String baseUrl,
    int moduleId,
    String newName,
  ) async {
    final params = {
      'component': 'core_course',
      'itemtype': 'activityname',
      'itemid': moduleId.toString(),
      'value': newName,
    };
    if (hasAjaxSession) {
      await _callAjax(baseUrl, 'core_update_inplace_editable', params);
      return;
    }
    try {
      await _callWs(
        baseUrl,
        token,
        'core_update_inplace_editable',
        usePost: true,
        params: params,
      );
    } catch (wsError) {
      throw MoodleException(
        'Sessão AJAX: ${_sessionError ?? "não disponível"}. '
        'WS: $wsError',
      );
    }
  }

  Future<void> updateLabelContent(
    String token,
    String baseUrl,
    int moduleId,
    String htmlContent,
  ) async {
    final params = {
      'component': 'mod_label',
      'itemtype': 'content',
      'itemid': moduleId.toString(),
      'value': htmlContent,
    };
    if (hasAjaxSession) {
      await _callAjax(baseUrl, 'core_update_inplace_editable', params);
      return;
    }
    try {
      await _callWs(
        baseUrl,
        token,
        'core_update_inplace_editable',
        usePost: true,
        params: params,
      );
    } catch (wsError) {
      throw MoodleException(
        'Sessão AJAX: ${_sessionError ?? "não disponível"}. '
        'WS: $wsError',
      );
    }
  }
}

class MoodleException implements Exception {
  final String message;
  MoodleException(this.message);
  @override
  String toString() => 'MoodleException: $message';
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  const ApiException(this.message, {this.sessionExpired = false});
  final String message;
  final bool sessionExpired;
  @override
  String toString() => message;
}

Uri serverUri(String value, {bool allowLocalHttp = kDebugMode}) {
  final uri = Uri.tryParse(value.trim());
  final local = uri != null &&
      (uri.host == 'localhost' ||
          uri.host == '127.0.0.1' ||
          uri.host == '10.0.2.2');
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      (uri.scheme != 'https' &&
          !(allowLocalHttp && local && uri.scheme == 'http'))) {
    throw const ApiException(
      'Indiquez une adresse HTTPS, sans chemin ni identifiants.',
    );
  }
  return uri.replace(path: '');
}

class GameApi {
  GameApi(this.server, {http.Client? client})
      : _client = client ?? http.Client();
  final Uri server;
  final http.Client _client;

  Future<Json> request(
    String path, {
    Json? data,
    Map<String, String>? query,
  }) async {
    try {
      final uri = server.replace(path: path, queryParameters: query);
      final response = await (data == null
              ? _client.get(uri)
              : _client.post(
                  uri,
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(data),
                ))
          .timeout(const Duration(seconds: 30));
      Json result;
      try {
        result = jsonDecode(response.body) as Json;
      } catch (_) {
        throw const ApiException(
          'Le serveur ne répond pas comme Quartiers. Vérifiez son adresse.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = result['error'] as String? ?? 'Erreur du serveur.';
        throw ApiException(
          message,
          sessionExpired:
              message == 'Salon introuvable' || message == 'Session invalide.',
        );
      }
      return result;
    } on TimeoutException {
      throw const ApiException(
        'Le serveur met trop de temps à répondre. Réessayez dans un instant.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Connexion impossible. Vérifiez Internet et l’adresse du serveur.',
      );
    }
  }

  Future<void> health() async {
    final result = await request('/api/health');
    if (result['app'] != 'quartiers') {
      throw const ApiException(
        'Cette adresse ne correspond pas à un serveur Quartiers.',
      );
    }
  }

  void close() => _client.close();
}

/// Only the packaged game's state/action routes can use the native session.
class RendererTransport {
  RendererTransport(this.api, this.session);
  final GameApi api;
  final Json session;

  Future<Json> handle(Json request) async {
    Json response(int status, Json body) =>
        {'status': status, 'body': jsonEncode(body)};
    try {
      final uri = api.server.resolve(request['url'] as String);
      final method = request['method'];
      if (uri.origin != api.server.origin ||
          uri.userInfo.isNotEmpty ||
          !((method == 'GET' &&
                  ['/api/state', '/api/health'].contains(uri.path)) ||
              (method == 'POST' && uri.path == '/api/action'))) {
        return response(403, {'error': 'Requête non autorisée.'});
      }
      final result = await api.request(
        uri.path,
        query: method == 'GET' && uri.path == '/api/state'
            ? {
                'code': session['code'] as String,
                'token': session['token'] as String
              }
            : null,
        data: method == 'POST'
            ? {...jsonDecode(request['body'] as String) as Json, ...session}
            : null,
      );
      return response(200, result);
    } on ApiException catch (error) {
      return response(400, {'error': error.message});
    } catch (_) {
      return response(400, {'error': 'Requête du jeu invalide.'});
    }
  }
}

class GameState {
  GameState(this.json);
  final Json json;
  List<Json> get players => (json['players'] as List).cast<Json>();
  List<Json> get tiles => (json['tiles'] as List).cast<Json>();
  Json get current => players[json['turn'] as int];
  String get me => json['me'] as String;
  Json get player => players.firstWhere((p) => p['id'] == me);
  String get phase => json['phase'] as String;
  bool get myTurn => current['id'] == me && player['out'] != true;
  bool get rolled => json['rolled'] == true;
  List<Json> get debts => ((json['debts'] ?? []) as List).cast<Json>();
  Json? get offer => json['offer'] as Json?;
  List<Json> get events => ((json['events'] ?? []) as List).cast<Json>();
  List<int> get dice => (json['dice'] as List).cast<int>();
  List<String> get log => (json['log'] as List).cast<String>();
  String name(String id) => players.firstWhere(
        (p) => p['id'] == id,
        orElse: () => {'name': 'la banque'},
      )['name'] as String;
  bool get canAct =>
      phase == 'playing' && myTurn && debts.isEmpty && offer == null;

  bool canBuild(int index) {
    final tile = tiles[index];
    return canAct &&
        tile['owner'] == me &&
        tile['kind'] == 'property' &&
        tile['level'] < 5 &&
        player['money'] >= tile['build'] &&
        tiles.where((t) => t['group'] == tile['group']).every(
              (t) =>
                  t['owner'] == me &&
                  t['mortgaged'] != true &&
                  t['level'] >= tile['level'],
            );
  }

  bool tradable(int index) {
    final tile = tiles[index];
    return tile['price'] > 0 &&
        (tile['kind'] != 'property' ||
            tiles
                .where((t) => t['group'] == tile['group'])
                .every((t) => t['level'] == 0));
  }
}

/// A single poll can be active. Mutations wait for it to finish before sending.
/// A failed POST is never automatically repeated: it may have reached the server.
class GameController extends ChangeNotifier {
  GameController(this.preferences, {this.apiFactory = GameApi.new});
  final SharedPreferences preferences;
  final GameApi Function(Uri) apiFactory;
  GameApi? _api;
  Json? _session;
  GameState? state;
  String? error;
  bool busy = false;
  bool connected = false;
  bool _disposed = false;
  bool _paused = false;
  Timer? _timer;
  Future<void>? _polling;
  int _generation = 0;
  int _lastEvent = 0;
  int _failures = 0;
  final List<Json> cards = [];
  String get server => _api?.server.toString() ?? '';
  String get code => _session?['code'] as String? ?? '';
  Json get gameSession => Map<String, dynamic>.unmodifiable(_session ?? {});
  String get savedServer =>
      preferences.getString('server') ??
      const String.fromEnvironment(
        'API_URL',
        defaultValue: 'https://monopoly-mauve-tau.vercel.app',
      );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() async {
    if (savedServer.isEmpty) return;
    busy = true;
    _notify();
    try {
      _api = apiFactory(serverUri(savedServer));
      final saved = preferences.getString('session');
      if (saved != null) {
        final session = jsonDecode(saved) as Json;
        if (session['server'] == server) {
          _session = {'code': session['code'], 'token': session['token']};
          await poll(force: true);
        }
      }
    } catch (_) {
      error = 'La session enregistrée ne peut pas être restaurée.';
    } finally {
      busy = false;
      _schedulePoll();
    }
    _notify();
  }

  Future<void> configure(String value) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    GameApi? candidate;
    try {
      candidate = apiFactory(serverUri(value));
      await candidate.health();
      await leave();
      _api?.close();
      _api = candidate;
      candidate = null;
      await preferences.setString('server', server);
      connected = true;
    } catch (e) {
      error = e.toString();
    } finally {
      candidate?.close();
      busy = false;
      _schedulePoll();
      _notify();
    }
  }

  Future<void> enter(String name, {String? room, bool solo = false}) async {
    if (busy || _api == null) return;
    busy = true;
    error = null;
    _notify();
    try {
      await _polling;
      _session = await _api!.request(
        room == null ? '/api/create' : '/api/join',
        data: {
          'name': name.trim(),
          if (room != null) 'code': room.trim().toUpperCase(),
          if (solo) 'mode': 'solo',
        },
      );
      _lastEvent = 0;
      await preferences.setString('name', name.trim());
      await preferences.setString(
        'session',
        jsonEncode({..._session!, 'server': server}),
      );
      await poll(force: true);
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      _schedulePoll();
      _notify();
    }
  }

  Future<void> action(String type, {int? index, Json extra = const {}}) async {
    if (busy || _session == null) return;
    busy = true;
    error = null;
    _timer?.cancel();
    _notify();
    try {
      await _polling;
      await _api!.request(
        '/api/action',
        data: {
          ..._session!,
          'type': type,
          if (index != null) 'index': index,
          ...extra,
        },
      );
    } catch (e) {
      error = '$e';
    } finally {
      // Refresh even after an ambiguous timeout; never resend the command.
      await poll(preserveError: error != null, force: true);
      busy = false;
      _schedulePoll();
      _notify();
    }
  }

  Future<void> poll({bool preserveError = false, bool force = false}) {
    if (_polling != null) return _polling!;
    if (_session == null || _paused || _disposed || (busy && !force)) {
      return Future.value();
    }
    final generation = _generation;
    _timer?.cancel();
    _polling = _fetchState(generation, preserveError).whenComplete(() {
      _polling = null;
      _schedulePoll();
    });
    return _polling!;
  }

  void _schedulePoll() {
    _timer?.cancel();
    if (_disposed || _paused || _session == null || busy) return;
    final delay = _failures == 0 ? 900 : (2000 * _failures).clamp(2000, 10000);
    _timer = Timer(Duration(milliseconds: delay), () => poll());
  }

  Future<void> _fetchState(int generation, bool preserveError) async {
    try {
      final json = await _api!.request(
        '/api/state',
        query: {'code': code, 'token': _session!['token'] as String},
      );
      if (_disposed || generation != _generation) return;
      final next = GameState(json);
      if (state != null) {
        cards.addAll(
          next.events.where((e) => e['id'] > _lastEvent && e['type'] == 'card'),
        );
      }
      _lastEvent = json['eventSeq'] as int? ?? 0;
      state = next;
      final recovered = !connected;
      connected = true;
      _failures = 0;
      if (!preserveError && recovered) error = null;
    } catch (e) {
      if (_disposed || generation != _generation) return;
      connected = false;
      _failures++;
      error = e.toString();
      if (e is ApiException && e.sessionExpired) {
        await leave();
        error =
            'Cette partie a disparu ou la session a expiré. Créez un nouveau salon.';
      }
    }
    _notify();
  }

  void dismissCard() {
    if (cards.isNotEmpty) cards.removeAt(0);
    _notify();
  }

  void pause(bool value) {
    _paused = value;
    if (value) {
      _timer?.cancel();
    } else {
      poll();
    }
  }

  Future<void> leave() async {
    _generation++;
    _timer?.cancel();
    _session = null;
    state = null;
    error = null;
    cards.clear();
    _lastEvent = 0;
    await preferences.remove('session');
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _api?.close();
    super.dispose();
  }
}

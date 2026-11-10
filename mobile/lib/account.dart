import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'game.dart';

abstract class AccountTokenStore {
  Future<String?> read(String server);
  Future<void> write(String server, String token);
  Future<void> delete(String server);
}

class DeviceAccountTokenStore implements AccountTokenStore {
  const DeviceAccountTokenStore();
  static const storage = FlutterSecureStorage();
  String key(String server) => 'quartiers_google_$server';
  @override
  Future<String?> read(String server) => storage.read(key: key(server));
  @override
  Future<void> write(String server, String token) =>
      storage.write(key: key(server), value: token);
  @override
  Future<void> delete(String server) => storage.delete(key: key(server));
}

String? _initializedClient;
Future<String?> googleCredential(String clientId) async {
  if (_initializedClient == null) {
    await GoogleSignIn.instance.initialize(serverClientId: clientId);
    _initializedClient = clientId;
  } else if (_initializedClient != clientId) {
    throw const ApiException(
        'Redémarrez l’application après le changement de serveur Google.');
  }
  try {
    return (await GoogleSignIn.instance.authenticate()).authentication.idToken;
  } on GoogleSignInException catch (error) {
    if (error.code == GoogleSignInExceptionCode.canceled) return null;
    throw const ApiException(
        'Connexion Google impossible. Vérifiez Internet ou la configuration Google du jeu.');
  }
}

class GoogleAccountController extends ChangeNotifier {
  GoogleAccountController(
      {this.store = const DeviceAccountTokenStore(),
      this.login = googleCredential,
      this.apiFactory = GameApi.new});
  final AccountTokenStore store;
  final Future<String?> Function(String) login;
  final GameApi Function(Uri) apiFactory;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Json? account;
  String? token;
  String? error;
  bool busy = false;
  String server = '';

  Future<void> restore(String address) async {
    account = null;
    token = null;
    server = address;
    error = null;
    if (address.isEmpty) return;
    busy = true;
    _notify();
    GameApi? api;
    try {
      token = await store.read(address).timeout(const Duration(seconds: 3));
      if (token != null) {
        api = apiFactory(serverUri(address))..authToken = token;
        account = (await api.request('/api/auth/me'))['account'] as Json;
      }
    } catch (_) {
      token = null;
      account = null;
      // A network or keystore failure still leaves an actionable sign-in screen.
    } finally {
      api?.close();
      busy = false;
      _notify();
    }
  }

  Future<void> signIn(String address) async {
    if (busy) return;
    busy = true;
    error = null;
    server = address;
    _notify();
    GameApi? api;
    try {
      api = apiFactory(serverUri(address));
      final configuration = await api.request('/api/auth/config');
      if (configuration['configured'] != true) {
        throw const ApiException(
            'La connexion Google doit encore être configurée par le propriétaire du jeu.');
      }
      final credential = await login(configuration['clientId'] as String);
      if (credential == null) return;
      final result = await api.request('/api/auth/google', data: {
        'credential': credential,
        'nonce': configuration['nonce'],
        'platform': 'android'
      });
      final bearer = result['token'] as String;
      await store.write(address, bearer).timeout(const Duration(seconds: 5));
      token = bearer;
      account = result['account'] as Json;
    } catch (e) {
      error = e.toString();
    } finally {
      api?.close();
      busy = false;
      _notify();
    }
  }

  Future<void> signOut() async {
    final api = server.isEmpty
        ? null
        : (apiFactory(serverUri(server))..authToken = token);
    try {
      if (api != null && token != null) {
        await api.request('/api/auth/logout', data: {});
      }
    } catch (_) {/* Local sign-out remains available offline. */} finally {
      api?.close();
      try {
        if (server.isNotEmpty) {
          await store.delete(server).timeout(const Duration(seconds: 3));
        }
      } catch (_) {}
      if (_initializedClient != null) {
        try {
          await GoogleSignIn.instance
              .signOut()
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
      account = null;
      token = null;
      error = null;
      _notify();
    }
  }
}

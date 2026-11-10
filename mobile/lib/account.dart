import 'dart:async';
import 'dart:convert';

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
Future<void> initializeGoogle(String clientId) async {
  if (_initializedClient == null) {
    await GoogleSignIn.instance.initialize(serverClientId: clientId);
    _initializedClient = clientId;
  } else if (_initializedClient != clientId) {
    throw const ApiException(
        'Redémarrez l’application après le changement de serveur Google.');
  }
}

Future<String?> googleCredential(String clientId) async {
  await initializeGoogle(clientId);
  try {
    return (await GoogleSignIn.instance.authenticate()).authentication.idToken;
  } on GoogleSignInException catch (error) {
    if (error.code == GoogleSignInExceptionCode.canceled) return null;
    throw const ApiException(
        'Connexion Google impossible. Vérifiez Internet ou la configuration Google du jeu.');
  }
}

Future<String?> googleCredentialSilently(String clientId) async {
  try {
    await initializeGoogle(clientId);
    final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
    if (attempt == null) return null;
    return (await attempt.timeout(const Duration(seconds: 10)))
        ?.authentication
        .idToken;
  } catch (_) {
    return null;
  }
}

class GoogleAccountController extends ChangeNotifier {
  GoogleAccountController(
      {this.store = const DeviceAccountTokenStore(),
      this.login = googleCredential,
      this.silentLogin = googleCredentialSilently,
      this.apiFactory = GameApi.new});
  final AccountTokenStore store;
  final Future<String?> Function(String) login;
  final Future<String?> Function(String) silentLogin;
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
  bool restorePending = false;
  Json? rememberedAccount;
  String? rememberedAccountId;
  String server = '';

  Future<void> acceptSession(Json result, String address) async {
    final bearer = result['token'] as String;
    final verified = result['account'] as Json;
    await store
        .write(address, jsonEncode({'token': bearer, 'account': verified}))
        .timeout(const Duration(seconds: 5));
    token = bearer;
    account = verified;
    rememberedAccount = verified;
    rememberedAccountId = verified['id'] as String;
  }

  Future<void> restore(String address) async {
    if (busy) return;
    account = null;
    token = null;
    server = address;
    error = null;
    restorePending = false;
    if (address.isEmpty) return;
    busy = true;
    _notify();
    GameApi? api;
    try {
      final saved =
          await store.read(address).timeout(const Duration(seconds: 3));
      if (saved == null) return;
      // Read old opaque tokens too, so updating the APK does not erase a session.
      if (saved.startsWith('{')) {
        final record = jsonDecode(saved) as Json;
        token = record['token'] as String;
        rememberedAccount = record['account'] as Json;
        rememberedAccountId = rememberedAccount!['id'] as String;
      } else {
        token = saved;
      }
      restorePending = true;
      _notify();
      api = apiFactory(serverUri(address))..authToken = token;
      try {
        account = (await api.request('/api/auth/me'))['account'] as Json;
      } on ApiException catch (failure) {
        if (!failure.authenticationRequired) rethrow;
        final configuration = await api.request('/api/auth/config');
        if (configuration['configured'] != true) rethrow;
        final credential =
            await silentLogin(configuration['clientId'] as String);
        if (credential == null) {
          token = null;
          restorePending = false;
          error = 'Reconnectez-vous avec Google pour retrouver votre compte.';
          return;
        }
        final result = await api.request('/api/auth/google', data: {
          'credential': credential,
          'nonce': configuration['nonce'],
          'platform': 'android'
        });
        final verified = result['account'] as Json;
        if (rememberedAccountId != null &&
            rememberedAccountId != verified['id']) {
          api.authToken = result['token'] as String;
          await api.request('/api/auth/logout', data: {});
          token = null;
          restorePending = false;
          error = 'Sélectionnez le compte Google utilisé précédemment.';
          return;
        }
        await acceptSession(result, address);
      }
      restorePending = false;
    } on ApiException catch (failure) {
      account = null;
      if (failure.statusCode == 401) {
        token = null;
        restorePending = false;
        error = 'Reconnectez-vous avec Google pour retrouver votre compte.';
      } else {
        restorePending = true;
        error =
            'Le serveur est momentanément indisponible. Votre connexion enregistrée est conservée.';
      }
    } catch (_) {
      // Keep the device record on timeouts/offline errors. It may still be valid
      // when Render has finished waking up; never treat a timeout as a logout.
      account = null;
      restorePending = true;
      error =
          'Le serveur est momentanément indisponible. Votre connexion enregistrée est conservée.';
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
    restorePending = false;
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
      await acceptSession(result, address);
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
      rememberedAccount = null;
      rememberedAccountId = null;
      restorePending = false;
      error = null;
      _notify();
    }
  }
}

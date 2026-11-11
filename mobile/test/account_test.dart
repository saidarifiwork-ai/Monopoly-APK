import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quartiers_mobile/account.dart';
import 'package:quartiers_mobile/game.dart';
import 'package:quartiers_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_fakes.dart';

void main() {
  testWidgets('a long server wake-up retries without requesting Google again',
      (tester) async {
    SharedPreferences.setMockInitialValues({'server': 'https://game.example'});
    final store = MemoryAccountTokenStore();
    final profile = {'id': 'said', 'name': 'Said', 'picture': ''};
    final saved =
        jsonEncode({'token': 'remembered-bearer', 'account': profile});
    store.tokens['https://game.example'] = saved;
    var attempts = 0;
    final account = GoogleAccountController(
        store: store,
        login: (_) async => throw StateError('No interactive Google request'),
        silentLogin: (_) async =>
            throw StateError('No Google request for a server outage'),
        apiFactory: (uri) => GameApi(uri, client: MockClient((request) async {
              expect(
                  request.headers['Authorization'], 'Bearer remembered-bearer');
              return ++attempts < 5
                  ? http.Response(
                      '{"error":"Waking up","code":"STORAGE_UNAVAILABLE"}', 503)
                  : http.Response(jsonEncode({'account': profile}), 200);
            })));
    final game = GameController(await SharedPreferences.getInstance(),
        apiFactory: (uri) => GameApi(uri,
            client:
                MockClient((_) async => http.Response('{"games":[]}', 200))));
    await tester
        .pumpWidget(QuartiersApp(controller: game, accountController: account));
    await tester.pumpAndSettle();
    expect(account.restorePending, isTrue);
    for (final seconds in [5, 10, 20, 40]) {
      await tester.pump(Duration(seconds: seconds));
      await tester.pumpAndSettle();
    }
    expect(attempts, 5);
    expect(account.account, profile);
    expect(account.restorePending, isFalse);
    expect(await store.read('https://game.example'), saved);
    expect(find.text('Jouer contre le robot'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'pending reconnection pauses in the background and resumes on return',
      (tester) async {
    SharedPreferences.setMockInitialValues({'server': 'https://game.example'});
    final store = MemoryAccountTokenStore();
    final profile = {'id': 'said', 'name': 'Said', 'picture': ''};
    store.tokens['https://game.example'] =
        jsonEncode({'token': 'remembered-bearer', 'account': profile});
    var online = false, attempts = 0;
    final account = GoogleAccountController(
        store: store,
        silentLogin: (_) async => throw StateError('No Google request'),
        apiFactory: (uri) => GameApi(uri, client: MockClient((_) async {
              attempts++;
              return online
                  ? http.Response(jsonEncode({'account': profile}), 200)
                  : http.Response(
                      '{"error":"offline","code":"STORAGE_UNAVAILABLE"}', 503);
            })));
    final game = GameController(await SharedPreferences.getInstance(),
        apiFactory: (uri) => GameApi(uri,
            client:
                MockClient((_) async => http.Response('{"games":[]}', 200))));
    await tester
        .pumpWidget(QuartiersApp(controller: game, accountController: account));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 90));
    expect(attempts, 1);
    online = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(account.account, profile);
    expect(attempts, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Google sign-in is mandatory before any game controls are shown',
      (tester) async {
    SharedPreferences.setMockInitialValues({'server': ''});
    final game = GameController(await SharedPreferences.getInstance());
    final account = GoogleAccountController(store: MemoryAccountTokenStore());
    await tester
        .pumpWidget(QuartiersApp(controller: game, accountController: account));
    await tester.pumpAndSettle();
    expect(find.text('Continuer avec Google'), findsOneWidget);
    expect(find.text('Jouer contre le robot'), findsNothing);
    expect(find.text('Créer un salon entre amis'), findsNothing);
    expect(find.text('Reprendre ma partie'), findsNothing);
  });

  test(
      'Google credentials are exchanged for a server-verified profile and a secure device token',
      () async {
    final store = MemoryAccountTokenStore();
    final profile = {
      'id': 'google-account-id',
      'name': 'Said Google',
      'picture': ''
    };
    final controller = GoogleAccountController(
        store: store,
        login: (clientId) async {
          expect(clientId, 'public-client');
          return 'google-identity-token';
        },
        apiFactory: (server) =>
            GameApi(server, client: MockClient((request) async {
              if (request.url.path == '/api/auth/config') {
                return http.Response(
                    '{"configured":true,"clientId":"public-client","nonce":"challenge"}',
                    200);
              }
              if (request.url.path == '/api/auth/google') {
                expect(jsonDecode(request.body), {
                  'credential': 'google-identity-token',
                  'nonce': 'challenge',
                  'platform': 'android'
                });
                return http.Response(
                    jsonEncode(
                        {'token': 'private-app-bearer', 'account': profile}),
                    200);
              }
              expect(request.headers['Authorization'],
                  'Bearer private-app-bearer');
              return http.Response(
                  jsonEncode({'account': profile, 'ok': true}), 200);
            })));
    await controller.signIn('https://game.example');
    expect(controller.account, profile);
    expect(jsonDecode((await store.read('https://game.example'))!)['token'],
        'private-app-bearer');
    await controller.restore('https://game.example');
    expect(controller.account, profile);
    await controller.restore('https://other.example');
    expect(controller.account, isNull);
    await controller.restore('https://game.example');
    await controller.signOut();
    expect(controller.account, isNull);
    expect(await store.read('https://game.example'), isNull);
    controller.dispose();
  });

  test(
      'unconfigured Google never grants a game account or opens the Google SDK',
      () async {
    var opened = false;
    final controller = GoogleAccountController(
        store: MemoryAccountTokenStore(),
        login: (_) async {
          opened = true;
          return 'token';
        },
        apiFactory: (server) => GameApi(server,
            client: MockClient(
                (_) async => http.Response('{"configured":false}', 200))));
    await controller.signIn('https://game.example');
    expect(controller.account, isNull);
    expect(opened, isFalse);
    expect(controller.error, contains('configurée'));
    expect(controller.busy, isFalse);
    controller.dispose();
  });
  test(
      'account expiry and a seat owned by another account require different recovery',
      () async {
    for (final entry in [
      {'status': 401, 'code': 'AUTH_REQUIRED', 'auth': true, 'seat': false},
      {'status': 403, 'code': 'ACCOUNT_MISMATCH', 'auth': false, 'seat': true},
    ]) {
      final api = GameApi(Uri.parse('https://game.example'),
          client: MockClient((_) async => http.Response(
              jsonEncode({'code': entry['code'], 'error': 'Connexion requise'}),
              entry['status'] as int)));
      await expectLater(
          api.request('/api/state'),
          throwsA(isA<ApiException>()
              .having((e) => e.authenticationRequired, 'Google reconnection',
                  entry['auth'])
              .having((e) => e.sessionExpired, 'discard unowned seat',
                  entry['seat'])));
      api.close();
    }
  });
  test(
      'closing and reopening the APK restores the stored account without opening Google',
      () async {
    final store = MemoryAccountTokenStore();
    final profile = {'id': 'a', 'name': 'Said', 'picture': ''};
    store.tokens['https://game.example'] =
        jsonEncode({'token': 'saved-bearer', 'account': profile});
    var googleCalls = 0;
    final controller = GoogleAccountController(
        store: store,
        login: (_) async {
          googleCalls++;
          return null;
        },
        silentLogin: (_) async {
          googleCalls++;
          return null;
        },
        apiFactory: (server) =>
            GameApi(server, client: MockClient((request) async {
              expect(request.headers['Authorization'], 'Bearer saved-bearer');
              return http.Response(jsonEncode({'account': profile}), 200);
            })));
    await controller.restore('https://game.example');
    expect(controller.account, profile);
    expect(googleCalls, 0);
    expect(controller.restorePending, isFalse);
    controller.dispose();
  });

  test(
      'a temporary network failure keeps the remembered account for a later retry',
      () async {
    final store = MemoryAccountTokenStore();
    final profile = {'id': 'a', 'name': 'Said', 'picture': ''};
    final saved = jsonEncode({'token': 'saved-bearer', 'account': profile});
    store.tokens['https://game.example'] = saved;
    var offline = true;
    final controller = GoogleAccountController(
        store: store,
        silentLogin: (_) async =>
            throw StateError('Network errors must not open Google'),
        apiFactory: (server) =>
            GameApi(server, client: MockClient((request) async {
              if (offline) throw http.ClientException('offline');
              return http.Response(jsonEncode({'account': profile}), 200);
            })));
    await controller.restore('https://game.example');
    expect(controller.account, isNull);
    expect(controller.restorePending, isTrue);
    expect(controller.token, 'saved-bearer');
    expect(await store.read('https://game.example'), saved);
    offline = false;
    await controller.restore('https://game.example');
    expect(controller.account, profile);
    expect(controller.restorePending, isFalse);
    controller.dispose();
  });

  for (final wrongAccount in [false, true]) {
    test(
        'an expired server session silently renews only the same remembered Google account: wrong=$wrongAccount',
        () async {
      final store = MemoryAccountTokenStore();
      final original = {'id': 'a', 'name': 'Said', 'picture': ''};
      store.tokens['https://game.example'] =
          jsonEncode({'token': 'expired-bearer', 'account': original});
      final restored = {
        'id': wrongAccount ? 'b' : 'a',
        'name': 'Said',
        'picture': ''
      };
      var interactiveCalls = 0, silentCalls = 0, revoked = false;
      final controller = GoogleAccountController(
          store: store,
          login: (_) async {
            interactiveCalls++;
            return null;
          },
          silentLogin: (_) async {
            silentCalls++;
            return 'fresh-google-credential';
          },
          apiFactory: (server) =>
              GameApi(server, client: MockClient((request) async {
                switch (request.url.path) {
                  case '/api/auth/me':
                    return http.Response(
                        '{"code":"AUTH_REQUIRED","error":"Expired"}', 401);
                  case '/api/auth/config':
                    return http.Response(
                        '{"configured":true,"clientId":"public-client","nonce":"challenge"}',
                        200);
                  case '/api/auth/google':
                    expect(jsonDecode(request.body)['credential'],
                        'fresh-google-credential');
                    return http.Response(
                        jsonEncode(
                            {'token': 'renewed-bearer', 'account': restored}),
                        200);
                  case '/api/auth/logout':
                    revoked = true;
                    expect(request.headers['Authorization'],
                        'Bearer renewed-bearer');
                    return http.Response('{"ok":true}', 200);
                  default:
                    throw StateError('Unexpected request');
                }
              })));
      await controller.restore('https://game.example');
      expect(interactiveCalls, 0);
      expect(silentCalls, 1);
      expect(controller.restorePending, isFalse);
      if (wrongAccount) {
        expect(controller.account, isNull);
        expect(revoked, isTrue);
        expect(
            jsonDecode((await store.read('https://game.example'))!)['account']
                ['id'],
            'a');
      } else {
        expect(controller.account, original);
        expect(controller.token, 'renewed-bearer');
      }
      controller.dispose();
    });
  }
  testWidgets(
      'a waking server is retried without requiring a new Google selection',
      (tester) async {
    SharedPreferences.setMockInitialValues({'server': ''});
    final game = GameController(await SharedPreferences.getInstance());
    final account = DelayedRestoredAccount();
    await tester
        .pumpWidget(QuartiersApp(controller: game, accountController: account));
    await tester.pumpAndSettle();
    expect(find.text('Réessayer ma connexion'), findsOneWidget);
    expect(find.text('Continuer avec Google'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(account.attempts, 2);
    expect(find.text('Jouer contre le robot'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class DelayedRestoredAccount extends GoogleAccountController {
  DelayedRestoredAccount() : super(store: MemoryAccountTokenStore());
  int attempts = 0;
  @override
  Future<void> restore(String address) async {
    attempts++;
    restorePending = attempts == 1;
    if (!restorePending) {
      account = {'id': 'a', 'name': 'Said', 'picture': ''};
      token = 'test-token';
    }
    notifyListeners();
  }
}

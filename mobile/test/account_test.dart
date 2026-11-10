import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quartiers_mobile/account.dart';
import 'package:quartiers_mobile/game.dart';
import 'package:quartiers_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_fakes.dart';

void main() {
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
    expect(await store.read('https://game.example'), 'private-app-bearer');
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
}

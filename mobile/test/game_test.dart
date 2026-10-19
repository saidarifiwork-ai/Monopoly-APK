import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quartiers_mobile/game.dart';
import 'package:shared_preferences/shared_preferences.dart';

Json fixture() => {
      'code': 'ABC234',
      'me': 'a',
      'host': 'a',
      'phase': 'playing',
      'turn': 0,
      'rolled': false,
      'dice': [1, 2],
      'events': [],
      'eventSeq': 0,
      'log': [],
      'debts': [],
      'offer': null,
      'players': [
        {
          'id': 'a',
          'name': 'Said',
          'money': 1500,
          'pos': 0,
          'out': false,
          'jail': false,
          'jailCards': [],
          'jailTurns': 0,
        },
        {
          'id': 'b',
          'name': 'Ami',
          'money': 1500,
          'pos': 0,
          'out': false,
          'jail': false,
          'jailCards': [],
          'jailTurns': 0,
        },
      ],
      'tiles': [
        {
          'name': 'Départ',
          'owner': '',
          'price': 0,
          'kind': 'special',
          'group': -1,
          'level': 0,
          'color': '',
        },
        {
          'name': 'Chefchaouen',
          'owner': 'a',
          'price': 60,
          'kind': 'property',
          'build': 50,
          'level': 0,
          'group': 0,
          'mortgaged': false,
          'color': '#905b42',
          'rents': [2, 10, 30, 90, 160, 250],
        },
        {
          'name': 'Tétouan',
          'owner': 'a',
          'price': 60,
          'kind': 'property',
          'build': 50,
          'level': 0,
          'group': 0,
          'mortgaged': false,
          'color': '#905b42',
          'rents': [4, 20, 60, 180, 320, 450],
        },
      ],
    };

void main() {
  test(
    'production endpoints must be HTTPS and contain no credentials/path',
    () {
      expect(
        serverUri('https://example.com/').toString(),
        'https://example.com',
      );
      for (final url in [
        'http://example.com',
        'https://user:pass@example.com',
        'https://example.com/api',
        'https://example.com?q=a',
        'https://example.com#x',
      ]) {
        expect(
          () => serverUri(url, allowLocalHttp: false),
          throwsA(isA<ApiException>()),
        );
      }
      expect(
        serverUri('http://10.0.2.2:8787', allowLocalHttp: true).port,
        8787,
      );
      expect(
        () => serverUri('http://10.0.2.2:8787', allowLocalHttp: false),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'construction respects turn, complete group, balance, debt and mortgage',
    () {
      final json = fixture();
      final s = GameState(json);
      expect(s.canBuild(1), isTrue);
      s.tiles[1]['level'] = 1;
      expect(s.canBuild(1), isFalse);
      s.tiles[1]['level'] = 0;
      s.tiles[2]['mortgaged'] = true;
      expect(s.canBuild(1), isFalse);
      s.tiles[2]['mortgaged'] = false;
      json['turn'] = 1;
      expect(s.canBuild(1), isFalse);
      json['turn'] = 0;
      json['debts'] = [
        {'player': 'a', 'amount': 2000},
      ];
      expect(s.canBuild(1), isFalse);
    },
  );

  test(
    'API distinguishes invalid sessions from transport / HTML errors',
    () async {
      final api = GameApi(
        Uri.parse('https://test.example'),
        client: MockClient(
          (r) async => http.Response('{"error":"Session invalide."}', 400),
        ),
      );
      await expectLater(
        api.request('/api/state'),
        throwsA(
          isA<ApiException>().having((e) => e.sessionExpired, 'expired', true),
        ),
      );
      api.close();
      final html = GameApi(
        Uri.parse('https://test.example'),
        client: MockClient(
          (r) async => http.Response('<html>Gateway error</html>', 502),
        ),
      );
      await expectLater(
        html.health(),
        throwsA(
          isA<ApiException>().having((e) => e.sessionExpired, 'expired', false),
        ),
      );
      html.close();
    },
  );

  test(
      'restore, serialize poll/action, preserve session offline, expire explicitly',
      () async {
    SharedPreferences.setMockInitialValues({
      'server': 'https://test.example',
      'session': jsonEncode({
        'server': 'https://test.example',
        'code': 'ABC234',
        'token': 'private',
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final json = fixture();
    final calls = <String>[];
    Completer<void>? pending;
    Completer<void>? mutationPending;
    var offline = false;
    var expired = false;
    var actionFailed = false;
    final c = GameController(
      prefs,
      apiFactory: (uri) => GameApi(
        uri,
        client: MockClient((r) async {
          calls.add(r.url.path);
          if (r.url.path == '/api/action') {
            expect(jsonDecode(r.body)['token'], 'private');
            if (mutationPending != null) await mutationPending.future;
            if (actionFailed) throw http.ClientException('offline');
            return http.Response('{"ok":true}', 200);
          }
          if (pending != null) await pending.future;
          if (expired) {
            return http.Response('{"error":"Salon introuvable"}', 400);
          }
          if (offline) throw http.ClientException('offline');
          return http.Response(jsonEncode(json), 200);
        }),
      ),
    );
    await c.restore();
    expect(c.state!.me, 'a');
    pending = Completer<void>();
    final poll = c.poll();
    final same = c.poll();
    expect(identical(poll, same), isTrue);
    final action = c.action('roll');
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((p) => p == '/api/action'), isEmpty);
    pending.complete();
    pending = null;
    await action;
    expect(calls.where((p) => p == '/api/action').length, 1);
    mutationPending = Completer<void>();
    final slowAction = c.action('end');
    await Future<void>.delayed(Duration.zero);
    final before = calls.where((p) => p == '/api/state').length;
    await c.poll();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(calls.where((p) => p == '/api/state').length, before,
        reason: 'polls must not overlap an in-flight mutation');
    mutationPending.complete();
    mutationPending = null;
    await slowAction;
    offline = true;
    await c.poll();
    expect(c.state, isNotNull);
    expect(prefs.getString('session'), isNotNull);
    actionFailed = true;
    await c.action('roll');
    expect(
      calls.where((p) => p == '/api/action').length,
      3,
      reason: 'failed POST must not be retried',
    );
    offline = false;
    expired = true;
    await c.poll();
    expect(c.state, isNull);
    expect(prefs.getString('session'), isNull);
    c.dispose();
  });

  test(
    'new card events are queued once; restore does not replay old events',
    () async {
      SharedPreferences.setMockInitialValues({
        'server': 'https://test.example',
        'session': jsonEncode({
          'server': 'https://test.example',
          'code': 'ABC234',
          'token': 't',
        }),
      });
      final json = fixture();
      json['events'] = [
        {'id': 1, 'type': 'card', 'title': 'ancienne'},
      ];
      json['eventSeq'] = 1;
      final c = GameController(
        await SharedPreferences.getInstance(),
        apiFactory: (uri) => GameApi(
          uri,
          client: MockClient((r) async => http.Response(jsonEncode(json), 200)),
        ),
      );
      await c.restore();
      expect(c.cards, isEmpty);
      (json['events'] as List).add({
        'id': 2,
        'type': 'card',
        'title': 'nouvelle',
      });
      json['eventSeq'] = 2;
      await c.poll();
      await c.poll();
      expect(c.cards.length, 1);
      c.dismissCard();
      expect(c.cards, isEmpty);
      c.dispose();
    },
  );
}

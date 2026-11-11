import 'package:flutter_test/flutter_test.dart';
import 'package:quartiers_mobile/game.dart';

// Explicit opt-in: this creates disposable rooms on a local development server.
const address = String.fromEnvironment('SMOKE_SERVER');

void main() {
  test('real API: friends lobby, opening order, movement and solo robot',
      () async {
    final api = GameApi(serverUri(address));
    addTearDown(api.close);
    await api.health();
    Future<void> authenticate(GameApi target, String identity) async {
      final config = await target.request('/api/auth/config');
      final result = await target.request('/api/auth/google', data: {
        'credential': 'fixture:$identity',
        'nonce': config['nonce'],
        'platform': 'android'
      });
      target.authToken = result['token'] as String;
    }

    await authenticate(api, 'said');
    final friendApi = GameApi(serverUri(address));
    addTearDown(friendApi.close);
    await authenticate(friendApi, 'abdo');
    final host =
        await api.request('/api/create', data: {'name': 'Test Android'});
    final friend = await friendApi
        .request('/api/join', data: {'name': 'Test ami', 'code': host['code']});
    GameApi client(Json who) =>
        who['token'] == friend['token'] ? friendApi : api;
    Future<GameState> state(Json who) async =>
        GameState(await client(who).request('/api/state', query: {
          'code': who['code'] as String,
          'token': who['token'] as String,
        }));
    Future<void> action(Json who, String type) async {
      await client(who).request('/api/action', data: {...who, 'type': type});
    }

    var s = await state(host);
    expect(s.tiles.length, 40);
    expect(s.players.length, 2);
    expect(s.players.every((p) => !p.containsKey('token')), isTrue);
    await action(host, 'start');
    for (var i = 0; i < 40; i++) {
      s = await state(host);
      if (s.phase == 'playing') break;
      await action(s.myTurn ? host : friend, 'orderroll');
    }
    s = await state(host);
    expect(s.phase, 'playing');
    final current = s.myTurn ? host : friend;
    final other = s.myTurn ? friend : host;
    await action(current, 'roll');
    s = await state(current);
    expect(s.events.any((e) => e['type'] == 'move'), isTrue);
    await expectLater(action(other, 'roll'), throwsA(isA<ApiException>()));
    final tile = s.tiles[s.player['pos'] as int];
    if (tile['price'] > 0 &&
        tile['owner'] == '' &&
        s.player['money'] >= tile['price']) {
      await action(current, 'auction');
      await expectLater(action(current, 'end'), throwsA(isA<ApiException>()));
      await client(current).request('/api/action',
          data: {...current, 'type': 'bid', 'amount': 1});
      await action(other, 'auctionpass');
      final next = await state(current);
      expect(next.json['auction'], isNull);
      expect(next.tiles[s.player['pos'] as int]['owner'], next.me);
      expect(next.player['money'], s.player['money'] - 1);
    }
    await action(current, 'end');
    // A second device knows the Google account, but has never saved this room.
    final otherDevice = GameApi(serverUri(address));
    addTearDown(otherDevice.close);
    await authenticate(otherDevice, 'said');
    final discovered =
        (await otherDevice.request('/api/my-games'))['games'] as List;
    expect(discovered.any((g) => g['code'] == host['code']), isTrue);
    final before = await state(host);
    final claimed =
        await otherDevice.request('/api/resume', data: {'code': host['code']});
    final transferred = GameState(await otherDevice.request('/api/state',
        query: {'code': claimed['code'], 'token': claimed['token']}));
    expect(transferred.me, before.me);
    expect(transferred.player['money'], before.player['money']);
    expect(transferred.player['pos'], before.player['pos']);
    await expectLater(state(host),
        throwsA(isA<ApiException>().having((e) => e.seatMoved, 'moved', true)));
    final returned =
        await api.request('/api/resume', data: {'code': host['code']});
    host['token'] = returned['token'];
    expect((await state(host)).me, before.me);
    await expectLater(
        otherDevice.request('/api/state',
            query: {'code': claimed['code'], 'token': claimed['token']}),
        throwsA(isA<ApiException>().having((e) => e.seatMoved, 'moved', true)));

    final solo = await api.request('/api/create',
        data: {'name': 'Test robot', 'mode': 'solo', 'botLevel': 'ultimate'});
    s = await state(solo);
    expect(s.phase, 'opening');
    expect(s.players.where((p) => p['bot'] == true).length, 4);
    expect(
        s.players
            .where((p) => p['bot'] == true)
            .every((p) => p['botLevel'] == 'ultimate'),
        isTrue);
    expect(
        s.players.firstWhere((p) => p['bot'] == true)['botLevel'], 'ultimate');
    final bots =
        s.players.where((p) => p['bot'] == true).map((p) => p['id']).toSet();
    final deadline = DateTime.now().add(const Duration(seconds: 55));
    while (DateTime.now().isBefore(deadline)) {
      s = await state(solo);
      if (s.events
          .any((e) => e['type'] == 'move' && bots.contains(e['playerId']))) {
        break;
      }
      final auction = s.json['auction'];
      if (auction != null) {
        if (auction['respondent'] == s.me) await action(solo, 'auctionpass');
      } else if (s.myTurn) {
        if (s.phase == 'opening') {
          await action(solo, 'orderroll');
        } else if (s.phase == 'playing') {
          await action(solo, s.rolled ? 'end' : 'roll');
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    expect(
        s.events
            .any((e) => e['type'] == 'move' && bots.contains(e['playerId'])),
        isTrue,
        reason: 'The robot must actually take a turn, not just join the room.');
  },
      timeout: const Timeout(Duration(seconds: 80)),
      skip: address.isEmpty
          ? 'Run with --dart-define=SMOKE_SERVER=http://127.0.0.1:8787'
          : false);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:quartiers_mobile/game.dart';

const room = String.fromEnvironment('WINDOWS_3D_SMOKE_ROOM');
const server = String.fromEnvironment('WINDOWS_3D_SMOKE_SERVER');

void main() {
  test('Flutter joins the same room as web and Godot', () async {
    final api = GameApi(serverUri(server));
    addTearDown(api.close);
    final session = await api.request('/api/join', data: {
      'name': 'Client Android',
      'code': room,
    });
    final deadline = DateTime.now().add(const Duration(seconds: 35));
    while (DateTime.now().isBefore(deadline)) {
      final state = await api.request('/api/state', query: {
        'code': session['code'] as String,
        'token': session['token'] as String,
      });
      final players = state['players'] as List;
      if (players.length >= 3) {
        final current = players[state['turn'] as int] as Map;
        if (current['id'] == state['me'] && state['phase'] == 'opening') {
          await api
              .request('/api/action', data: {...session, 'type': 'orderroll'});
        } else if (current['id'] == state['me'] &&
            state['phase'] == 'playing' &&
            state['rolled'] == false) {
          await api.request('/api/action', data: {...session, 'type': 'roll'});
        }
        if ((state['events'] as List).any((event) => event['type'] == 'move')) {
          expect(state['me'], isNotEmpty);
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    fail('Le client Flutter n’a pas reçu le démarrage du salon partagé.');
  },
      skip: room.isEmpty || server.isEmpty
          ? 'Test d’interopérabilité à lancer avec un salon local.'
          : false);
}

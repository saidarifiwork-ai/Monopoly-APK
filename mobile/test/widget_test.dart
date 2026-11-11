import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quartiers_mobile/game.dart';
import 'package:quartiers_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_test.dart' show fixture;
import 'account_fakes.dart';

void main() {
  for (final cached in [false, true]) {
    testWidgets('resume from welcome with cached session: $cached',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'server': 'https://test.example',
        if (cached)
          'session': jsonEncode({
            'server': 'https://test.example',
            'code': 'ABC234',
            'token': 'old-seat'
          })
      });
      var claimed = false;
      final c = GameController(await SharedPreferences.getInstance(),
          apiFactory: (uri) => GameApi(uri, client: MockClient((r) async {
                if (r.url.path == '/api/my-games') {
                  return http.Response(
                      jsonEncode({
                        'games': [
                          {
                            'code': 'ABC234',
                            'mode': 'friends',
                            'playerCount': 2,
                            'money': 1500,
                            'phase': 'playing'
                          }
                        ]
                      }),
                      200);
                }
                if (r.url.path == '/api/resume') {
                  claimed = true;
                  return http.Response(
                      '{"code":"ABC234","token":"new-seat"}', 200);
                }
                return http.Response(jsonEncode(fixture()), 200);
              })));
      await tester.pumpWidget(QuartiersApp(
          controller: c,
          accountController: SignedInTestAccount(),
          gameViewBuilder: (game, onHome) =>
              const Center(child: Text('Partie retrouvée'))));
      await tester.pumpAndSettle();
      expect(find.text('Reprendre ma partie'), findsOneWidget);
      await tester.ensureVisible(find.text('Reprendre ma partie'));
      await tester.tap(find.text('Reprendre ma partie'));
      await tester.pumpAndSettle();
      expect(find.text('Partie retrouvée'), findsOneWidget);
      expect(c.state!.me, 'a');
      expect(claimed, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('six bot difficulties can be selected on the native welcome',
      (tester) async {
    SharedPreferences.setMockInitialValues({'server': ''});
    final controller = GameController(await SharedPreferences.getInstance());
    await tester.pumpWidget(QuartiersApp(
        controller: controller, accountController: SignedInTestAccount()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Normal'));
    await tester.tap(find.text('Normal'));
    await tester.pumpAndSettle();
    for (final level in [
      'Débutant',
      'Facile',
      'Normal',
      'Difficile',
      'Expert',
      'Ultime'
    ]) {
      expect(find.text(level), findsWidgets);
    }
    await tester.tap(find.text('Ultime').last);
    await tester.pumpAndSettle();
    expect(find.text('Ultime'), findsOneWidget);
    expect(find.text('Affronter 4 robots Ultime'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final entry in {'Difficile': 2, 'Expert': 3, 'Ultime': 4}.entries) {
    testWidgets(
        'solo button announces ${entry.value} opponents for ${entry.key}',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'server': ''});
      final controller = GameController(await SharedPreferences.getInstance());
      await tester.pumpWidget(QuartiersApp(
          controller: controller, accountController: SignedInTestAccount()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Normal'));
      await tester.tap(find.text('Normal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key).last);
      await tester.pumpAndSettle();
      final button = find.text('Affronter ${entry.value} robots ${entry.key}');
      await tester.ensureVisible(button);
      expect(button, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('phone welcome validates name and fits with large text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final c = GameController(await SharedPreferences.getInstance(),
        apiFactory: (server) => GameApi(server,
            client: MockClient(
                (_) async => http.Response(jsonEncode({'games': []}), 200))));
    await tester.pumpWidget(
        QuartiersApp(controller: c, accountController: SignedInTestAccount()));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.ensureVisible(find.text('Jouer contre le robot'));
    await tester.tap(find.text('Jouer contre le robot'));
    await tester.pump();
    expect(find.text('Indiquez votre prénom.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    testWidgets('native welcome hands the game to the original renderer $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      // Empty server prevents network restore during this layout test.
      await prefs.setString('server', '');
      final c = GameController(prefs)
        ..state = GameState(fixture())
        ..connected = true;
      await tester.pumpWidget(QuartiersApp(
          controller: c,
          accountController: SignedInTestAccount(),
          gameViewBuilder: (game, onHome) =>
              const Center(child: Text('Rendu original embarqué'))));
      await tester.pump();
      expect(find.text('Reprendre ma partie'), findsOneWidget);
      expect(find.text('Rendu original embarqué'), findsNothing);
      await tester.tap(find.text('Reprendre ma partie'));
      await tester.pump();
      expect(find.text('Rendu original embarqué'), findsOneWidget);
      expect(find.text('QUARTIERS'), findsNothing);
      expect(tester.takeException(), isNull);
      await c.leave();
      await tester.pumpAndSettle();
      expect(find.text('Jouer contre le robot'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

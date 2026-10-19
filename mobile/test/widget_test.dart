import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quartiers_mobile/game.dart';
import 'package:quartiers_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_test.dart' show fixture;

void main() {
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
    final c = GameController(await SharedPreferences.getInstance());
    await tester.pumpWidget(QuartiersApp(controller: c));
    await tester.pump();
    await tester.ensureVisible(find.text('Jouer contre le robot'));
    await tester.tap(find.text('Jouer contre le robot'));
    await tester.pump();
    expect(find.text('Indiquez votre prénom.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    testWidgets('game and bottom controls fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      // Empty server prevents network restore during this layout test.
      await prefs.setString('server', '');
      final json = fixture();
      final templates = (json['tiles'] as List).cast<Json>();
      json['tiles'] = List.generate(
        40,
        (i) => {...templates[i % 3], 'owner': i == 0 ? '' : 'a'},
      );
      final c = GameController(prefs)
        ..state = GameState(json)
        ..connected = true;
      await tester.pumpWidget(QuartiersApp(controller: c));
      await tester.pump();
      expect(find.text('🎲 Lancer les dés'), findsOneWidget);
      expect(find.text('SALON '), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Joueurs'), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Joueurs'));
      await tester.pumpAndSettle();
      expect(find.text('À la table'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

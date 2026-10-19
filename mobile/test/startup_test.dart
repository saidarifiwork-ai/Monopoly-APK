import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quartiers_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first frame is visible while native storage is pending',
      (tester) async {
    final pending = Completer<SharedPreferences>();
    await tester.pumpWidget(AppStartup(loadPreferences: () => pending.future));
    expect(find.text('QUARTIERS MAROC'), findsOneWidget);
    expect(find.text('Ouverture de votre table…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
    expect(find.text('Réessayer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('storage failure is recoverable and retry reaches the welcome',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var attempts = 0;
    await tester.pumpWidget(AppStartup(loadPreferences: () {
      if (++attempts == 1) throw StateError('storage unavailable');
      return SharedPreferences.getInstance();
    }));
    await tester.pumpAndSettle();
    expect(find.text('Réessayer'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Jouer contre le robot'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

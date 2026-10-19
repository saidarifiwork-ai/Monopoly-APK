import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'game.dart';

/// The game's original HTML/SVG/CSS/JavaScript renderer, bundled in the APK.
/// Only the surrounding navigation is adapted; no remote website is loaded.
class OriginalGameScreen extends StatefulWidget {
  const OriginalGameScreen({
    super.key,
    required this.game,
    required this.onHome,
  });
  final GameController game;
  final Future<void> Function() onHome;
  @override
  State<OriginalGameScreen> createState() => _OriginalGameScreenState();
}

class _OriginalGameScreenState extends State<OriginalGameScreen>
    with WidgetsBindingObserver {
  WebViewController? web;
  String? failure;
  bool loading = true;
  bool ready = false;
  Timer? loadTimeout;
  late final GameApi api;
  late final RendererTransport transport;

  @override
  void initState() {
    super.initState();
    api = GameApi(serverUri(widget.game.server));
    transport = RendererTransport(api, widget.game.gameSession);
    WidgetsBinding.instance.addObserver(this);
    unawaited(initialize());
  }

  Future<void> initialize() async {
    loadTimeout?.cancel();
    loadTimeout = Timer(const Duration(seconds: 15), () {
      if (mounted && !ready) {
        setState(() => failure =
            'Le chargement du jeu ne répond pas. Réessayez ou revenez à l’accueil.');
      }
    });
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(const Color(0xFFEEE9DD));
      await controller.enableZoom(true);
      await controller.addJavaScriptChannel('QuartiersNative',
          onMessageReceived: receive);
      await controller.setOnJavaScriptConfirmDialog((request) async {
        if (!mounted) return false;
        return await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                      title: const Text('Confirmer'),
                      content: Text(request.message),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Annuler')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Confirmer')),
                      ],
                    )) ??
            false;
      });
      await controller.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          return uri?.scheme == 'file' &&
                  uri!.path
                      .startsWith('/android_asset/flutter_assets/assets/game/')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onWebResourceError: (error) {
          if (mounted && error.isForMainFrame == true) {
            loadTimeout?.cancel();
            setState(() => failure = 'Le jeu n’a pas pu être chargé.');
          }
        },
      ));
      if (!mounted) return;
      setState(() => web = controller);
      await controller.loadFlutterAsset('assets/game/index.html');
    } catch (_) {
      loadTimeout?.cancel();
      if (mounted) {
        setState(() => failure =
            'Impossible de charger le jeu sur cet appareil. Mettez Android System WebView à jour.');
      }
    }
  }

  void receive(JavaScriptMessage message) {
    if (!mounted) return;
    final dynamic payload;
    try {
      payload = jsonDecode(message.message);
    } catch (_) {
      return;
    }
    if (payload is! Map) return;
    switch (payload['type']) {
      case 'ready':
        unawaited(evaluate('startQuartiers(${jsonEncode({
              'server': widget.game.server,
              'session': {'code': widget.game.code, 'token': 'native-session'},
            })})'));
      case 'request':
        if (payload['id'] is int) {
          unawaited(forward(Map<String, dynamic>.from(payload)));
        }
      case 'loaded':
        loadTimeout?.cancel();
        setState(() {
          loading = false;
          ready = true;
        });
      case 'home':
        unawaited(widget.onHome());
      case 'invite':
        unawaited(Clipboard.setData(ClipboardData(text: widget.game.code)));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Code du salon copié.')));
      case 'expired':
        unawaited(widget.game.leave());
      case 'error':
        loadTimeout?.cancel();
        setState(
            () => failure = 'Les fichiers du jeu n’ont pas pu être chargés.');
    }
  }

  Future<void> evaluate(String javascript) async {
    try {
      await web?.runJavaScript(javascript);
    } catch (_) {
      if (mounted) {
        setState(() => failure = 'Le jeu a été interrompu. Réessayez.');
      }
    }
  }

  Future<void> forward(Json request) async {
    final result = await transport.handle(request);
    if (!mounted) return;
    await evaluate(
        'window.quartiersResolve(${request['id']}, ${jsonEncode(result)})');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ready) return;
    unawaited(evaluate(state == AppLifecycleState.resumed
        ? 'window.quartiersMobileResume?.()'
        : 'window.quartiersMobilePause?.()'));
  }

  @override
  void dispose() {
    loadTimeout?.cancel();
    api.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFFEEE9DD),
        child: Stack(children: [
          if (web != null && failure == null) WebViewWidget(controller: web!),
          if (loading && failure == null)
            const Center(child: CircularProgressIndicator()),
          if (failure != null)
            Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(failure!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: () {
                            setState(() {
                              failure = null;
                              loading = true;
                              ready = false;
                            });
                            unawaited(initialize());
                          },
                          child: const Text('Réessayer')),
                      TextButton(
                          onPressed: widget.onHome,
                          child: const Text('Accueil')),
                    ]))),
        ]),
      );
}

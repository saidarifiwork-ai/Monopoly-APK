import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'original_game.dart';
import 'game.dart';

const ink = Color(0xFF183C33);
const cream = Color(0xFFF7F2E7);
const gold = Color(0xFFE7BC59);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppStartup());
}

/// Paint a first frame before invoking native storage, including after updates.
class AppStartup extends StatefulWidget {
  const AppStartup({super.key, this.loadPreferences});
  final Future<SharedPreferences> Function()? loadPreferences;
  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  late Future<SharedPreferences> preferences;
  GameController? game;
  @override
  void initState() {
    super.initState();
    preferences = load();
  }

  Future<SharedPreferences> load() async {
    await WidgetsBinding.instance.endOfFrame;
    return Future<SharedPreferences>.sync(
      widget.loadPreferences ?? SharedPreferences.getInstance,
    ).timeout(const Duration(seconds: 10));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SharedPreferences>(
        future: preferences,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            game ??= GameController(snapshot.requireData);
            return QuartiersApp(controller: game!);
          }
          return MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                backgroundColor: cream,
                body: SafeArea(
                    child: Center(
                        child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('QUARTIERS MAROC',
                        style: TextStyle(
                            fontSize: 24,
                            color: ink,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 24),
                    if (!snapshot.hasError) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      const Text('Ouverture de votre table…'),
                    ] else ...[
                      const Text(
                          'L’application n’a pas pu lire ses réglages. Vos données n’ont pas été effacées.',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: () {
                            setState(() {
                              preferences = load();
                            });
                          },
                          child: const Text('Réessayer')),
                    ],
                  ]),
                ))),
              ));
        },
      );
}

typedef GameViewBuilder = Widget Function(
    GameController game, Future<void> Function() onHome);

class QuartiersApp extends StatelessWidget {
  const QuartiersApp(
      {super.key, required this.controller, this.gameViewBuilder});
  final GameController controller;
  final GameViewBuilder? gameViewBuilder;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Quartiers Maroc',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: cream,
          colorScheme: ColorScheme.fromSeed(
            seedColor: ink,
            primary: ink,
            secondary: gold,
            surface: cream,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: cream,
            foregroundColor: ink,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        home:
            GameHome(controller: controller, gameViewBuilder: gameViewBuilder),
      );
}

class GameHome extends StatefulWidget {
  const GameHome({super.key, required this.controller, this.gameViewBuilder});
  final GameController controller;
  final GameViewBuilder? gameViewBuilder;
  @override
  State<GameHome> createState() => _GameHomeState();
}

class _GameHomeState extends State<GameHome> with WidgetsBindingObserver {
  GameController get c => widget.controller;
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  final room = TextEditingController();
  bool leaving = false;
  bool gameOpened = false;
  bool settingsOpen = false;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: c.preferences.getString('name') ?? '');
    WidgetsBinding.instance.addObserver(this);
    c.addListener(onChange);
    unawaited(c.restore());
  }

  void onChange() {
    if (!mounted) return;
    if (c.state == null) gameOpened = false;
    // The original renderer owns polling and animations while a game is open.
    c.pause(c.state != null);
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      c.pause(c.state != null || state != AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(onChange);
    c.dispose();
    name.dispose();
    room.dispose();
    super.dispose();
  }

  Future<void> configure() async {
    final input = TextEditingController(
      text: c.server.isEmpty ? c.savedServer : c.server,
    );
    settingsOpen = true;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Serveur de jeu'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Le solo et les salons nécessitent Internet. Indiquez l’adresse du serveur Quartiers.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: input,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Adresse HTTPS',
                  hintText: 'https://votre-jeu.onrender.com',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              unawaited(c.configure(input.text));
            },
            child: const Text('Vérifier et connecter'),
          ),
        ],
      ),
    );
    settingsOpen = false;
    // A dialog route may still animate for a frame after pop.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    input.dispose();
  }

  Future<void> enter({bool solo = false, bool join = false}) async {
    if (!form.currentState!.validate()) return;
    if (join &&
        !RegExp(r'^[A-Z2-9]{6}$').hasMatch(room.text.trim().toUpperCase())) {
      message('Saisissez le code à 6 caractères de votre ami.');
      return;
    }
    if (c.server.isEmpty) {
      await configure();
      return;
    }
    await c.enter(name.text, solo: solo, room: join ? room.text : null);
    if (mounted && c.state != null && c.error == null) {
      setState(() => gameOpened = true);
    }
  }

  void message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<bool> confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> leave() async {
    if (leaving) return;
    leaving = true;
    try {
      if (await confirm('Revenir à l’accueil ?',
          'Votre place restera dans le salon, mais cet appareil oubliera sa session. Un joueur absent peut bloquer la partie.')) {
        await c.leave();
      }
    } finally {
      leaving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = gameOpened ? c.state : null;
    return PopScope(
      canPop: state == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !c.busy) unawaited(leave());
      },
      child: Scaffold(
        appBar: state == null
            ? AppBar(
                title: const Text('QUARTIERS',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, letterSpacing: 2)),
                actions: [
                  IconButton(
                      tooltip: 'Configurer le serveur',
                      onPressed: c.busy || settingsOpen ? null : configure,
                      icon: const Icon(Icons.settings_outlined))
                ],
              )
            : null,
        body: SafeArea(
            child: state != null
                ? (widget.gameViewBuilder?.call(c, leave) ??
                    OriginalGameScreen(game: c, onHome: leave))
                : Column(children: [
                    if (c.busy) const LinearProgressIndicator(minHeight: 2),
                    if (c.error != null)
                      Container(
                          width: double.infinity,
                          color: const Color(0xFFFFE4D6),
                          padding: const EdgeInsets.all(16),
                          child: Text(c.error!)),
                    Expanded(child: welcome()),
                  ])),
      ),
    );
  }

  Widget welcome() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.state != null) ...[
                    FilledButton.icon(
                      onPressed: c.busy
                          ? null
                          : () => setState(() => gameOpened = true),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Reprendre ma partie'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.landscape_rounded, color: gold, size: 48),
                        SizedBox(height: 20),
                        Text(
                          'Un lancer.\nUne ville.\nVotre empire.',
                          style: TextStyle(
                            fontSize: 36,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'ÉDITION MAROC  ·  40 CASES',
                          style: TextStyle(color: gold, letterSpacing: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Installez-vous à la table.',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: name,
                    maxLength: 20,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Votre prénom',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Indiquez votre prénom.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: c.busy ? null : () => enter(solo: true),
                    icon: const Icon(Icons.smart_toy_outlined),
                    label: const Text('Jouer contre le robot'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: c.busy ? null : enter,
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Créer un salon entre amis'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('OU REJOINDRE'),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                  ),
                  TextField(
                    controller: room,
                    maxLength: 6,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Code du salon',
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: c.busy ? null : () => enter(join: true),
                    child: const Text('Rejoindre mes amis'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    c.server.isEmpty
                        ? 'Connexion Internet requise · configurez votre serveur ⚙'
                        : 'Connexion Internet requise · ${Uri.parse(c.server).host}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

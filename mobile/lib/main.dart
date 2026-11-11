import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'original_game.dart';
import 'game.dart';
import 'account.dart';

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
                    Image.asset('assets/game/logo.png',
                        width: 96, height: 96, excludeFromSemantics: true),
                    const SizedBox(height: 20),
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
      {super.key,
      required this.controller,
      this.gameViewBuilder,
      this.accountController});
  final GameController controller;
  final GameViewBuilder? gameViewBuilder;
  final GoogleAccountController? accountController;
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
        home: GameHome(
            controller: controller,
            gameViewBuilder: gameViewBuilder,
            accountController: accountController),
      );
}

class GameHome extends StatefulWidget {
  const GameHome(
      {super.key,
      required this.controller,
      this.gameViewBuilder,
      this.accountController});
  final GameController controller;
  final GameViewBuilder? gameViewBuilder;
  final GoogleAccountController? accountController;
  @override
  State<GameHome> createState() => _GameHomeState();
}

class _GameHomeState extends State<GameHome> with WidgetsBindingObserver {
  GameController get c => widget.controller;
  late final GoogleAccountController a;
  bool expiringAccount = false;
  bool restoringAccount = false;
  Timer? accountRetry;
  int restoreRetries = 0;
  String? lastAccount;
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  final room = TextEditingController();
  bool leaving = false;
  bool gameOpened = false;
  bool settingsOpen = false;
  String botLevel = 'normal';
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: c.preferences.getString('name') ?? '');
    WidgetsBinding.instance.addObserver(this);
    c.addListener(onChange);
    a = widget.accountController ?? GoogleAccountController();
    a.rememberedAccountId = c.preferences.getString('google_account_id');
    a.addListener(onAccountChange);
    c.onAuthenticationRequired = () => unawaited(restoreAccount());
    unawaited(restoreAccount());
  }

  Future<void> restoreAccount() async {
    if (restoringAccount || a.busy || !mounted) return;
    restoringAccount = true;
    c.pause(true);
    accountRetry?.cancel();
    try {
      await a.restore(c.savedServer);
      if (!mounted) return;
      c.setAuthToken(a.token);
      if (a.account != null) c.pause(false);
      await c.restore(restoreSession: a.account != null);
      if (a.restorePending &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed)) {
        final attempt = restoreRetries < 4 ? restoreRetries++ : 4;
        final delay = [5, 10, 20, 40, 60][attempt];
        accountRetry = Timer(Duration(seconds: delay), () {
          if (mounted) unawaited(restoreAccount());
        });
      } else if (a.account != null) {
        restoreRetries = 0;
      }
    } finally {
      restoringAccount = false;
    }
  }

  void onAccountChange() {
    if (!mounted) return;
    c.setAuthToken(a.token);
    if (a.account != null && lastAccount != a.account!['id']) {
      lastAccount = a.account!['id'] as String;
      final value = a.account!['name'] as String;
      name.text = value.length > 20 ? value.substring(0, 20) : value;
    }
    if (a.account == null) gameOpened = false;
    setState(() {});
  }

  Future<void> signIn() async {
    accountRetry?.cancel();
    await a.signIn(c.savedServer);
    if (!mounted || a.account == null) return;
    final previous = c.preferences.getString('google_account_id');
    if (previous != null && previous != a.account!['id']) await c.leave();
    await c.preferences
        .setString('google_account_id', a.account!['id'] as String);
    c.setAuthToken(a.token);
    c.pause(false);
    await c.restore();
  }

  Future<void> expireAccount() async {
    if (expiringAccount) return;
    accountRetry?.cancel();
    expiringAccount = true;
    try {
      await a.signOut();
      await c.leave();
    } finally {
      expiringAccount = false;
    }
  }

  Future<void> signOut() async {
    if (c.state != null) {
      try {
        await c.relinquish();
      } catch (_) {}
    }
    await expireAccount();
  }

  void onChange() {
    if (!mounted) return;
    if (c.state == null) gameOpened = false;
    // The original renderer owns polling and animations while a game is open.
    c.pause(c.state != null);
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    c.pause(c.state != null || state != AppLifecycleState.resumed);
    if (state != AppLifecycleState.resumed) {
      accountRetry?.cancel();
    } else if (a.restorePending) {
      unawaited(restoreAccount());
    } else if (a.account != null) {
      unawaited(c.discoverGames());
    }
  }

  @override
  void dispose() {
    accountRetry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(onChange);
    a.removeListener(onAccountChange);
    a.dispose();
    c.onAuthenticationRequired = null;
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
              unawaited(changeServer(input.text));
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

  Future<void> changeServer(String value) async {
    await c.configure(value);
    if (!mounted || c.error != null) return;
    await a.restore(c.savedServer);
    c.setAuthToken(a.token);
  }

  Future<void> enter({bool solo = false, bool join = false}) async {
    if (a.account == null) return;
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
    await c.enter(name.text,
        solo: solo, room: join ? room.text : null, botLevel: botLevel);
    if (mounted && c.state != null && c.error == null) {
      setState(() => gameOpened = true);
    }
  }

  Future<void> resumeGame(String code) async {
    await c.resume(code);
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
      if (await confirm('Quitter la partie ?',
          'Un robot prendra le relais. Vous pourrez reprendre votre place avec le même compte Google.')) {
        try {
          // Dispose the renderer and stop its heartbeat before handing over.
          if (mounted) setState(() => gameOpened = false);
          await WidgetsBinding.instance.endOfFrame;
          await c.relinquish();
          await c.discoverGames();
        } catch (_) {
          if (mounted) message('Impossible de prévenir le serveur. Réessayez.');
        }
      }
    } finally {
      leaving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = gameOpened && a.account != null ? c.state : null;
    return PopScope(
      canPop: state == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !c.busy) unawaited(leave());
      },
      child: Scaffold(
        appBar: state == null
            ? AppBar(
                leading: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Image.asset('assets/game/logo.png',
                        excludeFromSemantics: true)),
                title: const Text('QUARTIERS',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, letterSpacing: 2)),
                actions: [
                  IconButton(
                      tooltip: 'Configurer le serveur',
                      onPressed:
                          c.busy || a.busy || settingsOpen ? null : configure,
                      icon: const Icon(Icons.settings_outlined))
                ],
              )
            : null,
        body: SafeArea(
            child: state != null
                ? (widget.gameViewBuilder?.call(c, leave) ??
                    OriginalGameScreen(game: c, onHome: leave))
                : Column(children: [
                    if (c.busy || a.busy)
                      const LinearProgressIndicator(minHeight: 2),
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

  Widget welcome() => LayoutBuilder(builder: (context, constraints) {
        final portrait = constraints.maxWidth < 550 &&
            constraints.maxHeight > constraints.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/game/welcome-background.png',
              fit: BoxFit.cover,
              alignment: const Alignment(0.65, 0),
              excludeFromSemantics: true,
            ),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, portrait ? 320 : 24, 20, 24),
              child: Align(
                alignment:
                    portrait ? Alignment.topCenter : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cream.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white70),
                      boxShadow: const [
                        BoxShadow(color: Color(0x30183C33), blurRadius: 24),
                      ],
                    ),
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (a.account == null) ...[
                            const Text('Bienvenue à la table.',
                                style: TextStyle(
                                    fontSize: 25, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 16),
                            const Text(
                                'Connectez-vous pour jouer. Votre compte reprend votre nom et votre photo Google.'),
                            const SizedBox(height: 20),
                            if (a.restorePending) ...[
                              Text(a.rememberedAccount == null
                                  ? 'Reprise de votre connexion…'
                                  : 'Reconnexion de ${a.rememberedAccount!['name']}…'),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                  onPressed: a.busy || c.busy
                                      ? null
                                      : () {
                                          restoreRetries = 0;
                                          unawaited(restoreAccount());
                                        },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Réessayer ma connexion')),
                            ] else
                              OutlinedButton.icon(
                                onPressed: a.busy || c.busy ? null : signIn,
                                icon: const Text('G',
                                    style: TextStyle(
                                        color: Color(0xFF4285F4),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 23)),
                                label: const Text('Continuer avec Google'),
                              ),
                            const SizedBox(height: 12),
                            const Text(
                                'Compte de jeu gratuit · connexion obligatoire',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12)),
                            if (a.error != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Text(a.error!,
                                      style:
                                          const TextStyle(color: Colors.red))),
                          ] else ...[
                            Row(children: [
                              CircleAvatar(
                                  backgroundImage:
                                      (a.account!['picture'] as String? ?? '')
                                              .isEmpty
                                          ? null
                                          : NetworkImage(
                                              a.account!['picture'] as String),
                                  child:
                                      (a.account!['picture'] as String? ?? '')
                                              .isEmpty
                                          ? const Icon(Icons.person)
                                          : null),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(a.account!['name'] as String,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold))),
                            ]),
                            Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                    onPressed: c.busy ? null : signOut,
                                    child: const Text('Se déconnecter'))),
                            if (c.gamesError != null) ...[
                              Text(c.gamesError!),
                              TextButton(
                                  onPressed: c.discoveringGames
                                      ? null
                                      : c.discoverGames,
                                  child: const Text('Actualiser mes parties')),
                            ],
                            for (final game in c.resumableGames.where((g) =>
                                c.state == null || g['code'] != c.code)) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFE5EDDF),
                                    borderRadius: BorderRadius.circular(16)),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                          game['mode'] == 'solo'
                                              ? 'Partie solo en cours'
                                              : 'Partie entre amis en cours',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      Text(
                                          'Salon ${game['code']} · ${game['playerCount']} joueurs'),
                                      const SizedBox(height: 12),
                                      FilledButton.icon(
                                          onPressed: c.busy
                                              ? null
                                              : () => resumeGame(
                                                  game['code'] as String),
                                          icon: const Icon(Icons.play_arrow),
                                          label: Text(
                                              c.resumableGames.length == 1
                                                  ? 'Reprendre ma partie'
                                                  : 'Reprendre cette partie')),
                                    ]),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (c.state != null) ...[
                              FilledButton.icon(
                                onPressed: c.busy
                                    ? null
                                    : () {
                                        if (c.resumableGames
                                            .any((g) => g['code'] == c.code)) {
                                          unawaited(resumeGame(c.code));
                                        } else {
                                          setState(() => gameOpened = true);
                                        }
                                      },
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Reprendre ma partie'),
                              ),
                              const SizedBox(height: 16),
                            ],
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
                            DropdownButtonFormField<String>(
                              initialValue: botLevel,
                              decoration: const InputDecoration(
                                  labelText: 'Niveau du robot'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'beginner', child: Text('Débutant')),
                                DropdownMenuItem(
                                    value: 'easy', child: Text('Facile')),
                                DropdownMenuItem(
                                    value: 'normal', child: Text('Normal')),
                                DropdownMenuItem(
                                    value: 'hard', child: Text('Difficile')),
                                DropdownMenuItem(
                                    value: 'expert', child: Text('Expert')),
                                DropdownMenuItem(
                                    value: 'ultimate', child: Text('Ultime')),
                              ],
                              onChanged: c.busy
                                  ? null
                                  : (value) => setState(
                                      () => botLevel = value ?? 'normal'),
                            ),
                            if (botLevel == 'ultimate')
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                    'Toi contre deux robots indépendants : chacun joue pour lui.',
                                    style: TextStyle(color: ink)),
                              ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed:
                                  c.busy ? null : () => enter(solo: true),
                              icon: const Icon(Icons.smart_toy_outlined),
                              label: Text(botLevel == 'ultimate'
                                  ? 'Affronter deux robots Ultime'
                                  : 'Jouer contre le robot'),
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
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 12),
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
                              onPressed:
                                  c.busy ? null : () => enter(join: true),
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      });
}

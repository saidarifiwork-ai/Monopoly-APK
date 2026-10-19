import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'board.dart';
import 'game.dart';

const ink = Color(0xFF183C33);
const cream = Color(0xFFF7F2E7);
const gold = Color(0xFFE7BC59);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(QuartiersApp(controller: GameController(prefs)));
}

class QuartiersApp extends StatelessWidget {
  const QuartiersApp({super.key, required this.controller});
  final GameController controller;
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
        home: GameHome(controller: controller),
      );
}

class GameHome extends StatefulWidget {
  const GameHome({super.key, required this.controller});
  final GameController controller;
  @override
  State<GameHome> createState() => _GameHomeState();
}

class _GameHomeState extends State<GameHome> with WidgetsBindingObserver {
  GameController get c => widget.controller;
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  final room = TextEditingController();
  bool showingCard = false;
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
    setState(() {});
    if (c.cards.isNotEmpty && !showingCard) {
      showingCard = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => showCard());
    }
  }

  Future<void> showCard() async {
    if (!mounted || c.cards.isEmpty) {
      showingCard = false;
      return;
    }
    final card = c.cards.first;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(
          card['deck'] == 'chance'
              ? Icons.auto_awesome
              : Icons.inventory_2_outlined,
          color: ink,
          size: 40,
        ),
        title: Text(card['title'] as String),
        content: Text(card['text'] as String),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    showingCard = false;
    if (mounted) c.dismissCard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      c.pause(state != AppLifecycleState.resumed);
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
    if (await confirm(
      'Revenir à l’accueil ?',
      'Votre place restera dans le salon, mais cet appareil oubliera sa session. Un joueur absent peut bloquer la partie.',
    )) {
      await c.leave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = c.state;
    return PopScope(
      canPop: state == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !c.busy) unawaited(leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'QUARTIERS',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
          actions: [
            if (state == null)
              IconButton(
                tooltip: 'Configurer le serveur',
                onPressed: c.busy || settingsOpen ? null : configure,
                icon: const Icon(Icons.settings_outlined),
              ),
            if (state != null)
              IconButton(
                tooltip: 'Revenir à l’accueil',
                onPressed: c.busy ? null : leave,
                icon: const Icon(Icons.home_outlined),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (c.busy) const LinearProgressIndicator(minHeight: 2),
              if (c.error != null)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFFFE4D6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          c.error!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (state != null)
                        IconButton(
                          tooltip: 'Réessayer',
                          onPressed: c.busy ? null : () => c.poll(),
                          icon: const Icon(Icons.refresh),
                        ),
                    ],
                  ),
                ),
              Expanded(child: state == null ? welcome() : game(state)),
            ],
          ),
        ),
        bottomNavigationBar: state == null
            ? null
            : SafeArea(top: false, child: actionDock(state)),
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

  Widget game(GameState s) => RefreshIndicator(
        onRefresh: () => c.poll(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          children: [
            Row(
              children: [
                Icon(
                  c.connected ? Icons.cloud_done_outlined : Icons.cloud_off,
                  color: c.connected ? ink : Colors.red,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'SALON ${c.code}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: c.code));
                    message('Code du salon copié.');
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Inviter'),
                ),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < s.players.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        avatar: CircleAvatar(
                          backgroundColor: playerColors[i % 6],
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontSize: 11, color: ink),
                          ),
                        ),
                        side: BorderSide(
                          color: s.current['id'] == s.players[i]['id']
                              ? ink
                              : Colors.transparent,
                          width: 2,
                        ),
                        label: Text(
                          '${s.players[i]['name']}${s.players[i]['id'] == s.me ? ' · vous' : ''}\n${s.players[i]['out'] == true ? 'Faillite' : '${s.players[i]['money']} DH'}',
                          maxLines: 2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: GameBoard(state: s, onTile: property),
              ),
            ),
            if (s.phase == 'opening')
              box(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Qui commence ?',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Text(
                      'Le plus grand total commence. En cas d’égalité, les joueurs concernés relancent.',
                    ),
                    for (final p in s.players)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${p['name']} : ${((s.json['openingHistory'] as Json?)?[p['id']] as List? ?? []).join(' → ')}',
                        ),
                      ),
                  ],
                ),
              ),
            if (s.phase == 'finished')
              box(
                Text(
                  '🏆 ${s.current['name']} remporte la partie !',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: properties,
                  icon: const Icon(Icons.domain),
                  label: const Text('Mes biens'),
                ),
                OutlinedButton.icon(
                  onPressed: players,
                  icon: const Icon(Icons.people_outline),
                  label: const Text('Joueurs'),
                ),
                OutlinedButton.icon(
                  onPressed: journal,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Journal'),
                ),
              ],
            ),
            if (s.offer != null) offerPanel(s),
            if (s.debts.isNotEmpty) debtPanel(s),
            if (s.log.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(s.log.last, style: const TextStyle(fontSize: 13)),
              ),
          ],
        ),
      );

  Widget box(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      );

  Widget command(
    String label,
    String type, {
    bool secondary = false,
    int? index,
    Json extra = const {},
  }) {
    final enabled = !c.busy && c.connected && !showingCard;
    final callback =
        enabled ? () => c.action(type, index: index, extra: extra) : null;
    return secondary
        ? OutlinedButton(onPressed: callback, child: Text(label))
        : FilledButton(onPressed: callback, child: Text(label));
  }

  Widget actionDock(GameState s) {
    final buttons = <Widget>[];
    var title =
        '${s.current['name']} joue${s.current['bot'] == true ? ' · robot' : ''}';
    if (s.phase == 'lobby') {
      title = 'Invitez vos amis · ${s.players.length}/6 joueurs';
      if (s.json['host'] == s.me) {
        if (s.players.length < 6) {
          buttons.add(command('Ajouter un robot', 'addbot', secondary: true));
        }
        if (s.players.length >= 2) buttons.add(command('Commencer', 'start'));
      }
    } else if (s.phase == 'opening' && s.myTurn) {
      title = 'À vous de lancer pour votre place';
      buttons.add(command('Lancer les dés', 'orderroll'));
    } else if (s.debts.isNotEmpty) {
      title = 'Dette à régler · ouvrez Mes biens';
    } else if (s.offer != null) {
      title = 'Négociation en cours · voir l’offre';
    } else if (s.canAct) {
      title = 'À vous de jouer';
      if (!s.rolled) {
        if (s.player['jail'] == true) {
          title = 'Prison · tour ${(s.player['jailTurns'] as int) + 1}/3';
          if ((s.player['jailCards'] as List).isNotEmpty) {
            buttons.add(
              command('Utiliser ma carte', 'usejail', secondary: true),
            );
          }
          if ((s.player['jailTurns'] as int) < 2) {
            buttons.add(command('Tenter un double', 'roll', secondary: true));
          }
          buttons.add(command('Payer 50 DH et lancer', 'payjail'));
        } else {
          buttons.add(command('🎲 Lancer les dés', 'roll'));
        }
      } else {
        final t = s.tiles[s.player['pos'] as int];
        if (t['price'] > 0 &&
            t['owner'] == '' &&
            s.player['money'] >= t['price']) {
          buttons.add(command('Acheter · ${t['price']} DH', 'buy'));
        }
        final again = s.dice[0] == s.dice[1] &&
            s.player['jail'] != true &&
            s.player['jailDouble'] != true;
        buttons.add(
          command(
            again ? 'Rejouer mon double' : 'Terminer mon tour',
            'end',
            secondary: true,
          ),
        );
      }
    } else if (s.phase == 'finished') {
      title = 'Partie terminée';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 16)],
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .36,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (buttons.isNotEmpty) const SizedBox(height: 8),
              for (var i = 0; i < buttons.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                  child: buttons[i],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> sheet(String title, Widget Function(GameState) content) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final s = c.state;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .8,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (s != null) content(s),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> properties() => sheet('Mes biens', (s) {
        final owned = [
          for (var i = 0; i < s.tiles.length; i++)
            if (s.tiles[i]['owner'] == s.me) i,
        ];
        return Column(
          children: [
            if (owned.isEmpty) const Text('Vos achats apparaîtront ici.'),
            for (final i in owned)
              ListTile(
                minVerticalPadding: 12,
                leading: CircleAvatar(
                  backgroundColor: tileColor(s.tiles[i]),
                  child: const Icon(Icons.location_city, color: Colors.white),
                ),
                title: Text(s.tiles[i]['name'] as String),
                subtitle: Text(
                  '${s.tiles[i]['level']} construction(s)${s.tiles[i]['mortgaged'] == true ? ' · hypothéqué' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(property(i));
                },
              ),
          ],
        );
      });

  Future<void> players() => sheet(
        'À la table',
        (s) => Column(
          children: [
            for (var i = 0; i < s.players.length; i++)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: playerColors[i % 6],
                  child: Icon(
                    s.players[i]['bot'] == true
                        ? Icons.smart_toy
                        : Icons.person,
                    color: ink,
                  ),
                ),
                title: Text(
                  '${s.players[i]['name']}${s.players[i]['id'] == s.me ? ' · vous' : ''}',
                ),
                subtitle: Text(
                  '${s.players[i]['out'] == true ? 'Faillite' : s.players[i]['jail'] == true ? 'En prison' : s.tiles[s.players[i]['pos'] as int]['name']}',
                ),
                trailing: Text('${s.players[i]['money']} DH'),
              ),
          ],
        ),
      );

  Future<void> journal() => sheet(
        'Journal de la partie',
        (s) => Column(
          children: [
            for (final line in s.log.reversed)
              ListTile(
                dense: true,
                leading: const Icon(Icons.circle, size: 8),
                title: Text(line),
              ),
          ],
        ),
      );

  Future<void> property(int index) => sheet('Fiche de la case', (s) {
        final t = s.tiles[index];
        final mine = t['owner'] == s.me;
        final active =
            s.phase == 'playing' && s.player['out'] != true && s.offer == null;
        final group = s.tiles.where((x) => x['group'] == t['group']);
        final canSell = mine &&
            t['level'] > 0 &&
            group.every((x) => x['level'] <= t['level']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 8, color: tileColor(t)),
            const SizedBox(height: 16),
            Text(
              t['name'] as String,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            ),
            if (t['price'] > 0) ...[
              Text(
                'Prix : ${t['price']} DH · ${t['owner'] == '' ? 'Disponible' : s.name(t['owner'] as String)}',
              ),
              const SizedBox(height: 12),
              if (t['rents'] is List) ...[
                const Text(
                  'Loyers · le terrain nu rapporte le double avec la couleur complète.',
                ),
                for (var l = 0; l < (t['rents'] as List).length; l++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l == 0
                              ? 'Terrain nu'
                              : l == 5
                                  ? 'Hôtel'
                                  : '$l maison(s)',
                        ),
                        Text('${t['rents'][l]} DH'),
                      ],
                    ),
                  ),
                Text(
                    'Construction : ${t['build']} DH · niveau ${t['level']}/5'),
              ] else
                Text(
                  t['kind'] == 'station'
                      ? 'Loyer : 25 / 50 / 100 / 200 DH selon vos gares.'
                      : 'Loyer : 4 × les dés, ou 10 × avec les deux compagnies.',
                ),
              if (t['mortgaged'] == true)
                const Text(
                  'Hypothéqué · aucun loyer',
                  style: TextStyle(color: Colors.red),
                ),
              const SizedBox(height: 16),
              if (s.canBuild(index))
                command(
                  t['level'] == 4
                      ? 'Construire un hôtel'
                      : 'Construire une maison',
                  'build',
                  index: index,
                ),
              if (active && canSell)
                command(
                  'Vendre une construction · ${t['build'] ~/ 2} DH',
                  'sellhouse',
                  index: index,
                  secondary: true,
                ),
              if (active && mine && t['mortgaged'] != true && s.tradable(index))
                command(
                  'Hypothéquer · +${t['price'] ~/ 2} DH',
                  'mortgage',
                  index: index,
                  secondary: true,
                ),
              if (active && mine && t['mortgaged'] == true && s.debts.isEmpty)
                command(
                  'Lever l’hypothèque · ${t['price'] ~/ 2 + ((t['price'] / 2) / 10).ceil()} DH',
                  'unmortgage',
                  index: index,
                ),
              if (active &&
                  !mine &&
                  t['owner'] != '' &&
                  t['mortgaged'] != true &&
                  s.tradable(index))
                OutlinedButton(
                  onPressed: c.busy || !c.connected
                      ? null
                      : () {
                          Navigator.pop(context);
                          unawaited(makeOffer(index));
                        },
                  child: const Text('Faire une offre'),
                ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Cette case ne peut pas être achetée.'),
              ),
          ],
        );
      });

  Widget debtPanel(GameState s) {
    final d = s.debts.first;
    return box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Dette à régler',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          Text(
            '${s.name(d['player'] as String)} doit ${d['amount']} DH à ${s.name(d['receiver'] as String)}. La partie est en pause.',
          ),
          if (d['player'] == s.me) ...[
            const Text(
              'Vendez des constructions ou hypothéquez vos biens. Le paiement sera automatique dès que la somme sera réunie.',
            ),
            OutlinedButton(
              onPressed: properties,
              child: const Text('Gérer mes biens'),
            ),
            TextButton(
              onPressed: c.busy || !c.connected
                  ? null
                  : () async {
                      if (await confirm(
                        'Déclarer faillite ?',
                        'Vous abandonnerez vos biens et serez éliminé de cette partie.',
                      )) {
                        await c.action('bankrupt');
                      }
                    },
              child: const Text('Déclarer faillite'),
            ),
          ],
        ],
      ),
    );
  }

  Widget offerPanel(GameState s) {
    final o = s.offer!;
    final involved = [o['buyer'], o['seller']].contains(s.me);
    return box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Une offre sur la table',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          Text(
            '${s.name(o['buyer'] as String)} propose ${o['amount']} DH à ${s.name(o['seller'] as String)} pour ${s.tiles[o['index'] as int]['name']}.',
          ),
          if ((o['offered'] as List).isNotEmpty)
            Text(
              'Biens ajoutés : ${(o['offered'] as List).map((i) => s.tiles[i as int]['name']).join(', ')}',
            ),
          Text('Réponse attendue : ${s.name(o['respondent'] as String)}'),
          if (o['respondent'] == s.me) ...[
            command('Accepter', 'acceptoffer'),
            command('Refuser', 'rejectoffer', secondary: true),
            OutlinedButton(
              onPressed: c.busy || !c.connected
                  ? null
                  : () => makeOffer(o['index'] as int, counter: true),
              child: const Text('Faire une contre-offre'),
            ),
          ],
          if (involved)
            command('Annuler la négociation', 'canceloffer', secondary: true),
        ],
      ),
    );
  }

  Future<void> makeOffer(int index, {bool counter = false}) async {
    final s = c.state!;
    final amount = TextEditingController(
      text: '${counter ? s.offer!['amount'] : s.tiles[index]['price']}',
    );
    final selected = <int>{
      if (counter) ...(s.offer!['offered'] as List).cast<int>(),
    };
    final buyer = counter ? s.offer!['buyer'] : s.me;
    final eligible = [
      for (var i = 0; i < s.tiles.length; i++)
        if (i != index &&
            s.tiles[i]['owner'] == buyer &&
            s.tiles[i]['mortgaged'] != true &&
            s.tradable(i))
          i,
    ];
    final offerForm = GlobalKey<FormState>();
    final result = await showDialog<Json>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            counter ? 'Contre-offre' : 'Acheter ${s.tiles[index]['name']}',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Form(
                key: offerForm,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Montant en DH',
                      ),
                      validator: (value) {
                        final n = int.tryParse(value ?? '');
                        if (n == null || n <= 0) {
                          return 'Indiquez un montant supérieur à zéro.';
                        }
                        if (buyer == s.me && n > s.player['money']) {
                          return 'Vous n’avez pas assez de DH.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('Biens ajoutés par l’acheteur'),
                    for (final i in eligible)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.tiles[i]['name'] as String),
                        value: selected.contains(i),
                        onChanged: (checked) => setDialogState(() {
                          checked == true
                              ? selected.add(i)
                              : selected.remove(i);
                        }),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (offerForm.currentState!.validate()) {
                  Navigator.pop(context, <String, dynamic>{
                    'amount': int.parse(amount.text),
                    'offered': selected.toList(),
                  });
                }
              },
              child: const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    amount.dispose();
    if (result != null && mounted && c.state?.json['code'] == s.json['code']) {
      await c.action(
        counter ? 'counteroffer' : 'offer',
        index: index,
        extra: result,
      );
    }
  }
}

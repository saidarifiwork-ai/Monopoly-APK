import 'package:flutter/material.dart';

import 'game.dart';

const playerColors = [
  Color(0xFFEF7255),
  Color(0xFF63A9EE),
  Color(0xFFE7BC59),
  Color(0xFFC084CF),
  Color(0xFF66C49B),
  Color(0xFFEF94B3),
];

Color tileColor(Json tile) {
  final hex = (tile['color'] as String? ?? '').replaceFirst('#', '');
  return hex.length == 6
      ? Color(int.parse('FF$hex', radix: 16))
      : const Color(0xFFD8CDB2);
}

(int, int) boardPosition(int i) {
  if (i <= 10) return (10, 10 - i);
  if (i <= 20) return (20 - i, 0);
  if (i <= 30) return (0, i - 20);
  return (i - 30, 10);
}

class GameBoard extends StatefulWidget {
  const GameBoard({super.key, required this.state, required this.onTile});
  final GameState state;
  final ValueChanged<int> onTile;
  @override
  State<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends State<GameBoard> {
  final transform = TransformationController();
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: InteractiveViewer(
                transformationController: transform,
                minScale: 1,
                maxScale: 3.5,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final unit = constraints.maxWidth / 11;
                    final s = widget.state;
                    return ColoredBox(
                      color: const Color(0xFF254E44),
                      child: Stack(
                        children: [
                          Positioned(
                            left: unit,
                            top: unit,
                            right: unit,
                            bottom: unit,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.landscape_rounded,
                                    color: Color(0xFFE7BC59),
                                    size: 44,
                                  ),
                                  const SizedBox(height: 8),
                                  const FittedBox(
                                    child: Text(
                                      'QUARTIERS',
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const Text(
                                    'ÉDITION MAROC',
                                    style: TextStyle(
                                      color: Color(0xFFE7BC59),
                                      letterSpacing: 2,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: s.dice
                                        .map(
                                          (d) => Container(
                                            margin: const EdgeInsets.all(4),
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFF8E9),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                12,
                                              ),
                                            ),
                                            child: Text(
                                              '$d',
                                              style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFF17372F),
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    s.phase == 'lobby'
                                        ? 'Votre table vous attend'
                                        : s.current['name'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  Text(
                                    s.phase == 'opening'
                                        ? 'Qui commence ?'
                                        : 'Départ +200 DH',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          for (var i = 0; i < s.tiles.length; i++)
                            Positioned(
                              top: boardPosition(i).$1 * unit,
                              left: boardPosition(i).$2 * unit,
                              width: unit,
                              height: unit,
                              child: Semantics(
                                button: true,
                                label: 'Case $i, ${s.tiles[i]['name']}',
                                child: GestureDetector(
                                  onTap: () => widget.onTile(i),
                                  child: Container(
                                    margin: const EdgeInsets.all(.7),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF8E9),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          height: unit * .16,
                                          color: tileColor(s.tiles[i]),
                                        ),
                                        Expanded(
                                          child: Center(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 1,
                                              ),
                                              child: Text(
                                                s.tiles[i]['name'] as String,
                                                textAlign: TextAlign.center,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                textScaler:
                                                    TextScaler.noScaling,
                                                style: TextStyle(
                                                  fontSize: unit * .19,
                                                  height: 1.05,
                                                  fontWeight: FontWeight.w700,
                                                  color: s.tiles[i]
                                                              ['mortgaged'] ==
                                                          true
                                                      ? Colors.grey
                                                      : const Color(0xFF17372F),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          spacing: 1,
                                          children: [
                                            for (var p = 0;
                                                p < s.players.length;
                                                p++)
                                              if (s.players[p]['pos'] == i &&
                                                  s.players[p]['out'] != true)
                                                Container(
                                                  width: unit * .19,
                                                  height: unit * .19,
                                                  decoration: BoxDecoration(
                                                    color: playerColors[p % 6],
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Colors.white,
                                                      width: .7,
                                                    ),
                                                  ),
                                                ),
                                          ],
                                        ),
                                        if (s.tiles[i]['owner'] != '')
                                          Container(
                                            height: 2,
                                            color: playerColors[s.players
                                                .indexWhere(
                                                  (p) =>
                                                      p['id'] ==
                                                      s.tiles[i]['owner'],
                                                )
                                                .clamp(0, 5)],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pincez pour zoomer · touchez une ville',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              IconButton(
                tooltip: 'Recentrer le plateau',
                onPressed: () => transform.value = Matrix4.identity(),
                icon: const Icon(Icons.center_focus_strong, size: 19),
              ),
            ],
          ),
        ],
      );
}

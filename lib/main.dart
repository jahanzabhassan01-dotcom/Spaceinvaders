// main.dart
// ignore_for_file: deprecated_member_use, non_constant_identifier_names, use_build_context_synchronously

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: GamePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  // player & entities
  late Player player;
  List<Bullet> bullets = [];
  List<EnemyBase> enemies = [];
  List<Bullet> goblinArrows = [];
  Monster? monster;
  List<DeadCorpse> corpses = [];

  // timers & rng
  double fireTimer = 0;
  double enemySpawnTimer = 0;
  double monsterTimer = 0;
  final Random rng = Random();
  Timer? loop;

  // image assets map
  final Map<String, ui.Image> images = {};

  // filenames (must exactly match files in assets/images)
  final String playerFile = 'assets/images/fighter_jet.png';
  final List<String> enemyFrames = [
    'assets/images/enemy1.png',
    'assets/images/enemy2.png',
    'assets/images/enemy3.png',
  ];
  final List<String> goblinFrames = [
    'assets/images/goblin_arrow1.png',
    'assets/images/goblin_arrow2.png',
  ];
  final String goblinArrowFile = 'assets/images/goblin_arrow.png';
  final List<String> monsterFrames = [
    'assets/images/monster1.png',
    'assets/images/monster2.png',
    'assets/images/monster3.png',
  ];
  final String playerBulletFile = 'assets/images/bullet.png';

  ui.Image? playerImg;
  ui.Image? playerBulletImg;
  ui.Image? goblinArrowImg;

  Size screenSize = Size.zero;
  bool ready = false;
  bool gameOver = false;
  int score = 0;

  @override
  void initState() {
    super.initState();
    player = Player(position: const Offset(200, 600), size: const Size(50, 50), lives: 3);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAssets());
  }

  @override
  void dispose() {
    loop?.cancel();
    super.dispose();
  }

  Future<ui.Image> _loadImage(String path) async {
    final data = await rootBundle.load(path);
    final bytes = data.buffer.asUint8List();
    return await decodeImageFromList(bytes);
  }

  Future<void> _loadAssets() async {
    // load single images
    playerImg = await _loadImage(playerFile);
    playerBulletImg = await _loadImage(playerBulletFile);
    goblinArrowImg = await _loadImage(goblinArrowFile);

    // load frames into map
    for (final f in enemyFrames) {
      images[f] = await _loadImage(f);
    }
    for (final f in goblinFrames) {
      images[f] = await _loadImage(f);
    }
    for (final f in monsterFrames) {
      images[f] = await _loadImage(f);
    }
    images[goblinArrowFile] = goblinArrowImg!;

    // set screen size (safe because called after frame)
    screenSize = MediaQuery.of(context).size;
    // position player bottom center
    player.position = Offset(screenSize.width / 2, screenSize.height - 80);

    ready = true;
    // start game loop
    loop = Timer.periodic(const Duration(milliseconds: 16), _update);
    setState(() {});
  }

  void _update(Timer t) {
    if (!ready || gameOver) return;
    const double dt = 0.016;

    fireTimer += dt;
    enemySpawnTimer += dt;
    monsterTimer += dt;

    // auto-fire player bullets
    if (fireTimer > 0.25 && player.alive) {
      bullets.add(Bullet(
        pos: Offset(player.position.dx, player.position.dy - player.size.height / 2 - 6),
        size: const Size(10, 20),
        speed: 600,
        owner: BulletOwner.player,
      ));
      fireTimer = 0;
    }

    // spawn simple enemies
    if (enemySpawnTimer > 1.6) {
      final x = rng.nextDouble() * (screenSize.width - 60) + 30;
      enemies.add(Enemy(pos: Offset(x, -40), rng: rng, frames: enemyFrames));
      enemySpawnTimer = 0;
    }

    // occasionally spawn goblin
    if (rng.nextDouble() < 0.01) {
      final x = rng.nextDouble() * (screenSize.width - 80) + 40;
      enemies.add(Goblin(pos: Offset(x, -60), rng: rng, walkFrames: goblinFrames, arrowFile: goblinArrowFile));
    }

    // spawn monster rarely
    if (monster == null && monsterTimer > 18.0) {
      monster = Monster(pos: Offset(screenSize.width / 2, -150), rng: rng, frames: monsterFrames, width: 160);
      monsterTimer = 0;
    }

    // update bullets: player bullets move up
    for (int i = bullets.length - 1; i >= 0; i--) {
      bullets[i].pos = Offset(bullets[i].pos.dx, bullets[i].pos.dy - bullets[i].speed * dt);
      if (bullets[i].pos.dy < -40) bullets.removeAt(i);
    }

    // update enemies and goblins
    for (int i = enemies.length - 1; i >= 0; i--) {
      final e = enemies[i];
      e.update(dt, screenSize);

      // if goblin and should shoot, spawn goblin arrow
      if (e is Goblin) {
        if (e.shouldShoot) {
          goblinArrows.add(Bullet(
            pos: Offset(e.center.dx, e.center.dy + e.size.height / 2 + 8),
            size: const Size(14, 24),
            speed: 360,
            owner: BulletOwner.goblin,
          ));
          e.onShot();
        }
      }

      // if enemy touches player -> melee hit
      final rectE = Rect.fromCenter(center: e.center, width: e.sizeWidth, height: e.sizeHeight);
      final rectP = Rect.fromCenter(center: player.position, width: player.size.width, height: player.size.height);
      if (rectE.overlaps(rectP) && player.alive && !player.invincible) {
        player.takeHit();
        if (player.lives <= 0) {
          player.alive = false;
          gameOver = true;
        }
      }

      // remove if offscreen
      if (e.center.dy > screenSize.height + 80) enemies.removeAt(i);
    }

    // update monster (no shooting)
    if (monster != null) {
      monster!.update(dt, screenSize);
      final rectM = Rect.fromCenter(center: monster!.pos, width: monster!.width, height: monster!.height);
      final rectP = Rect.fromCenter(center: player.position, width: player.size.width, height: player.size.height);
      if (rectM.overlaps(rectP) && player.alive && !player.invincible) {
        player.takeHit();
        if (player.lives <= 0) {
          player.alive = false;
          gameOver = true;
        }
      }
      if (monster!.pos.dy > screenSize.height + 200) monster = null;
    }

    // update goblin arrows (move down)
    for (int i = goblinArrows.length - 1; i >= 0; i--) {
      goblinArrows[i].pos = Offset(goblinArrows[i].pos.dx, goblinArrows[i].pos.dy + goblinArrows[i].speed * dt);
      if (goblinArrows[i].pos.dy > screenSize.height + 60) {
        goblinArrows.removeAt(i);
      } else {
        // check collision with player
        final rA = Rect.fromCenter(center: goblinArrows[i].pos, width: goblinArrows[i].size.width, height: goblinArrows[i].size.height);
        final rP = Rect.fromCenter(center: player.position, width: player.size.width, height: player.size.height);
        if (rA.overlaps(rP) && player.alive && !player.invincible) {
          goblinArrows.removeAt(i);
          player.takeHit();
          if (player.lives <= 0) {
            player.alive = false;
            gameOver = true;
          }
        }
      }
    }

    // corpses (fall & fade)
    for (int i = corpses.length - 1; i >= 0; i--) {
      corpses[i].update(dt);
      if (corpses[i].life <= 0) corpses.removeAt(i);
    }

    // collisions: player bullets vs enemies & monster
    for (int i = bullets.length - 1; i >= 0; i--) {
      final b = bullets[i];
      bool hit = false;
      // enemies
      for (int j = enemies.length - 1; j >= 0; j--) {
        final e = enemies[j];
        final rB = Rect.fromCenter(center: b.pos, width: b.size.width, height: b.size.height);
        final rE = Rect.fromCenter(center: e.center, width: e.sizeWidth, height: e.sizeHeight);
        if (rB.overlaps(rE)) {
          // hit: spawn corpse (use dead goblin image if exists), remove enemy
          bullets.removeAt(i);
          hit = true;
          corpses.add(DeadCorpse(pos: e.center, imageFile: 'assets/images/dead_goblin.png', images: images));
          enemies.removeAt(j);
          score += 10;
          break;
        }
      }
      if (hit) continue;
      // monster
      if (monster != null) {
        final rB = Rect.fromCenter(center: b.pos, width: b.size.width, height: b.size.height);
        final rM = Rect.fromCenter(center: monster!.pos, width: monster!.width, height: monster!.height);
        if (rB.overlaps(rM)) {
          bullets.removeAt(i);
          monster!.hp -= 1;
          if (monster!.hp <= 0) {
            corpses.add(DeadCorpse(pos: monster!.pos, imageFile: 'assets/images/dead_goblin.png', images: images));
            monster = null;
            score += 200;
          }
        }
      }
    }

    setState(() {});
  }

  void restart() {
    bullets.clear();
    goblinArrows.clear();
    enemies.clear();
    corpses.clear();
    monster = null;
    player = Player(position: Offset(screenSize.width / 2, screenSize.height - 80), size: const Size(50, 50), lives: 3);
    score = 0;
    gameOver = false;
    setState(() {});
  }

  void _onDrag(DragUpdateDetails d) {
    if (!player.alive) return;
    setState(() {
      player.position = Offset(
        (player.position.dx + d.delta.dx).clamp(player.size.width / 2, screenSize.width - player.size.width / 2),
        (player.position.dy + d.delta.dy).clamp(player.size.height / 2, screenSize.height - player.size.height / 2),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (screenSize == Size.zero && mounted) {
      screenSize = MediaQuery.of(context).size;
      player.position = Offset(screenSize.width / 2, screenSize.height - 80);
    }

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: _onDrag,
        child: Stack(
          children: [
            CustomPaint(
              size: screenSize,
              painter: GamePainter(
                player: player,
                playerSprite: playerImg,
                bullets: bullets,
                enemies: enemies,
                enemyImages: images,
                goblinFrames: goblinFrames,
                goblinArrowImage: images[goblinArrowFile],
                monster: monster,
                monsterImages: images,
                goblinArrows: goblinArrows,
                playerBulletImage: playerBulletImg,
                corpses: corpses,
              ),
            ),

            // HUD
            Positioned(
              top: 12,
              left: 12,
              child: Row(
                children: [
                  for (int i = 0; i < player.lives; i++)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.favorite, color: Colors.redAccent, size: 22),
                    ),
                  const SizedBox(width: 10),
                  Text('Score: $score', style: const TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            ),

            // Game Over
            if (gameOver)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('GAME OVER', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 18),
                        ElevatedButton(onPressed: restart, child: const Text('Restart')),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------
// Core classes
// -----------------------------
class Player {
  Offset position;
  Size size;
  int lives;
  bool invincible = false;
  double invTimer = 0;
  bool alive = true;

  Player({required this.position, required this.size, this.lives = 3});

  void takeHit() {
    if (invincible) return;
    lives -= 1;
    invincible = true;
    invTimer = 1.4;
    // countdown
    Timer.periodic(const Duration(milliseconds: 100), (t) {
      invTimer -= 0.1;
      if (invTimer <= 0) {
        invincible = false;
        t.cancel();
      }
    });
  }
}

enum BulletOwner { player, goblin }

class Bullet {
  Offset pos;
  final Size size;
  double speed;
  final BulletOwner owner;
  Bullet({required this.pos, required this.size, required this.speed, required this.owner});
}

// Enemy base
abstract class EnemyBase {
  Offset pos;
  double speed;
  Size size;
  int frameIndex = 0;
  double frameTimer = 0;
  final Random rng;
  EnemyBase({required this.pos, required this.speed, required this.size, required this.rng});
  void update(double dt, Size screenSize);
  Offset get center => pos;
  double get sizeWidth => size.width;
  double get sizeHeight => size.height;
  double get size_width => size.width;
  double get size_height => size.height;
}

// Simple animated Enemy (melee)
class Enemy extends EnemyBase {
  List<String> frames;
  Enemy({required Offset pos, required Random rng, required this.frames})
      : super(pos: pos, speed: 40, size: const Size(50, 40), rng: rng);

  @override
  void update(double dt, Size screenSize) {
    pos = Offset(pos.dx, pos.dy + speed * dt);
    frameTimer += dt;
    if (frameTimer > 0.14) {
      frameIndex = (frameIndex + 1) % frames.length;
      frameTimer = 0;
    }
  }

  String get currentFrame => frames[frameIndex];
}

// Goblin: walks, then attacks by shooting goblin_arrow.png
class Goblin extends EnemyBase {
  final List<String> walkFrames;
  final String arrowFile;
  bool attacking = false;
  double attackTimer = 0;
  bool shouldShoot = false;

  Goblin({
    required Offset pos,
    required Random rng,
    required this.walkFrames,
    required this.arrowFile,
  }) : super(pos: pos, speed: 48, size: const Size(46, 46), rng: rng);

  @override
  void update(double dt, Size screenSize) {
    if (!attacking) {
      pos = Offset(pos.dx, pos.dy + speed * dt);
      frameTimer += dt;
      if (frameTimer > 0.16) {
        frameIndex = (frameIndex + 1) % walkFrames.length;
        frameTimer = 0;
      }
      if (pos.dy > screenSize.height * 0.45) {
        attacking = true;
        attackTimer = 0;
        shouldShoot = true; // shoot once immediately
      }
    } else {
      attackTimer += dt;
      if (attackTimer > 0.4) {
        frameIndex = (frameIndex + 1) % walkFrames.length;
        attackTimer = 0;
        shouldShoot = true;
      }
      // small bob while attacking
      pos = Offset(pos.dx, pos.dy + sin(attackTimer * 8) * 6 * dt);
    }
  }

  String get currentFrame => walkFrames[frameIndex % walkFrames.length];
  void onShot() => shouldShoot = false;
}

// Monster (melee, animated)
class Monster {
  Offset pos;
  double width;
  double height = 100;
  int hp = 60;
  final Random rng;
  List<String> frames;
  int frameIndex = 0;
  double frameTimer = 0;
  double moveTimer = 0;

  Monster({required this.pos, required this.rng, required this.width, required this.frames});

  void update(double dt, Size screenSize) {
    moveTimer += dt;
    pos = Offset((pos.dx + sin(moveTimer) * 40 * dt).clamp(60, screenSize.width - 60), pos.dy + 18 * dt);
    frameTimer += dt;
    if (frameTimer > 0.18) {
      frameIndex = (frameIndex + 1) % frames.length;
      frameTimer = 0;
    }
  }

  String get currentFrame => frames[frameIndex];
}

// corpse for death visuals
class DeadCorpse {
  Offset pos;
  String imageFile;
  Map<String, ui.Image> images;
  double life = 1.0;
  double fallSpeed = 80;
  double alpha = 1.0;
  DeadCorpse({required this.pos, required this.imageFile, required this.images});

  void update(double dt) {
    pos = Offset(pos.dx, pos.dy + fallSpeed * dt);
    life -= dt;
    alpha = (life / 1.0).clamp(0.0, 1.0);
  }

  ui.Image? get image => images[imageFile];
}

// -----------------------------
// Renderer / Painter
// -----------------------------
class GamePainter extends CustomPainter {
  final Player player;
  final ui.Image? playerSprite;
  final List<Bullet> bullets;
  final List<EnemyBase> enemies;
  final Map<String, ui.Image> enemyImages;
  final List<String> goblinFrames;
  final ui.Image? goblinArrowImage;
  final Monster? monster;
  final Map<String, ui.Image> monsterImages;
  final List<Bullet> goblinArrows;
  final ui.Image? playerBulletImage;
  final List<DeadCorpse> corpses;

  GamePainter({
    required this.player,
    required this.playerSprite,
    required this.bullets,
    required this.enemies,
    required this.enemyImages,
    required this.goblinFrames,
    required this.goblinArrowImage,
    required this.monster,
    required this.monsterImages,
    required this.goblinArrows,
    required this.playerBulletImage,
    required this.corpses,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.black);

    // corpses under everything
    for (final c in corpses) {
      final img = c.image;
      if (img != null) {
        final dst = Rect.fromCenter(center: c.pos, width: 48, height: 48);
        canvas.saveLayer(dst, Paint()..color = Colors.white.withOpacity(c.alpha));
        canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, paint);
        canvas.restore();
      }
    }

    // player (flash when invincible)
    if (playerSprite != null) {
      final dst = Rect.fromCenter(center: player.position, width: player.size.width, height: player.size.height);
      if (player.invincible) {
        canvas.saveLayer(dst, Paint());
        canvas.drawImageRect(playerSprite!, Rect.fromLTWH(0, 0, playerSprite!.width.toDouble(), playerSprite!.height.toDouble()), dst, paint);
        canvas.drawRect(dst, Paint()..color = Colors.red.withOpacity(0.22));
        canvas.restore();
      } else {
        canvas.drawImageRect(playerSprite!, Rect.fromLTWH(0, 0, playerSprite!.width.toDouble(), playerSprite!.height.toDouble()), dst, paint);
      }
    } else {
      // fallback
      canvas.drawRect(Rect.fromCenter(center: player.position, width: player.size.width, height: player.size.height), paint..color = Colors.white);
    }

    // player bullets
    for (final b in bullets) {
      if (playerBulletImage != null) {
        final dst = Rect.fromCenter(center: b.pos, width: b.size.width, height: b.size.height);
        canvas.drawImageRect(playerBulletImage!, Rect.fromLTWH(0, 0, playerBulletImage!.width.toDouble(), playerBulletImage!.height.toDouble()), dst, paint);
      } else {
        canvas.drawRect(Rect.fromCenter(center: b.pos, width: b.size.width, height: b.size.height), paint..color = Colors.yellowAccent);
      }
    }

    // enemies (enemy or goblin)
    for (final e in enemies) {
      if (e is Enemy) {
        final fname = e.currentFrame;
        final img = enemyImages[fname];
        if (img != null) {
          final dst = Rect.fromCenter(center: e.center, width: e.sizeWidth, height: e.sizeHeight);
          canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, paint);
        }
      } else if (e is Goblin) {
        final fname = e.currentFrame;
        final img = enemyImages[fname];
        if (img != null) {
          final dst = Rect.fromCenter(center: e.center, width: e.sizeWidth, height: e.sizeHeight);
          canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, paint);
        }
      }
    }

    // monster
    if (monster != null) {
      final img = monsterImages[monster!.currentFrame];
      if (img != null) {
        final dst = Rect.fromCenter(center: monster!.pos, width: monster!.width, height: monster!.height);
        canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, paint);
      }
    }

    // goblin arrows (projectiles)
    for (final a in goblinArrows) {
      if (goblinArrowImage != null) {
        final dst = Rect.fromCenter(center: a.pos, width: a.size.width, height: a.size.height);
        canvas.drawImageRect(goblinArrowImage!, Rect.fromLTWH(0, 0, goblinArrowImage!.width.toDouble(), goblinArrowImage!.height.toDouble()), dst, paint);
      } else {
        canvas.drawRect(Rect.fromCenter(center: a.pos, width: a.size.width, height: a.size.height), paint..color = Colors.orange);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

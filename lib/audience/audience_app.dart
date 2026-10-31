import 'dart:math' as math;
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../shared/protocol.dart';
import '../shared/theme.dart';

/// Layar penonton: judul + kartu-kartu nomor doorprize.
/// Dikendalikan penuh dari window operator via [DoorprizeProtocol.update].
class AudienceApp extends StatelessWidget {
  const AudienceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doorprize Display - Penonton',
      theme: buildTheme(),
      debugShowCheckedModeBanner: false,
      home: const AudienceScreen(),
    );
  }
}

class AudienceScreen extends StatefulWidget {
  const AudienceScreen({super.key});

  @override
  State<AudienceScreen> createState() => _AudienceScreenState();
}

class _AudienceScreenState extends State<AudienceScreen> {
  String _title = 'NOMOR DOORPRIZE';
  List<String> _numbers = [];

  @override
  void initState() {
    super.initState();
    _goFullscreen();
    // Mode bidirectional + operator juga daftar sebagai handler
    // (lihat AudienceChannel.initReceiver) — pola yang sama dipakai
    // aplikasi undian.
    WindowMethodChannel(
      DoorprizeProtocol.channelName,
      mode: ChannelMode.bidirectional,
    ).setMethodCallHandler(_onMethod);
  }

  Future<void> _onMethod(MethodCall call) async {
    if (call.method != DoorprizeProtocol.update) return;
    final args = (call.arguments as Map?)?.cast<String, Object?>();
    if (args == null || !mounted) return;
    setState(() {
      final t = (args[DoorprizeProtocol.argTitle] as String?)?.trim();
      _title = (t == null || t.isEmpty) ? 'NOMOR DOORPRIZE' : t;
      final raw = args[DoorprizeProtocol.argNumbers];
      _numbers = raw is List ? raw.map((e) => '$e').toList() : [];
    });
  }

  /// Pindah ke display non-utama (proyektor/TV) lalu fullscreen.
  Future<void> _goFullscreen() async {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setTitle('Doorprize Display - Penonton');
    } catch (_) {}
    try {
      final displays = await screenRetriever.getAllDisplays();
      Offset? target;
      for (final d in displays) {
        final pos = d.visiblePosition;
        if (pos != null && (pos.dx != 0 || pos.dy != 0)) {
          target = pos;
          break;
        }
      }
      if (target != null) {
        await windowManager.setPosition(target);
      }
    } catch (_) {
      // tetap lanjut fullscreen di display utama
    }
    try {
      await windowManager.setFullScreen(true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Tampilkan SEMUA nomor ronde aktif; kartu menyesuaikan ukuran otomatis.
    final shown = _numbers;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo selalu tampil — baik saat menunggu maupun saat
              // nomor sudah muncul (sesuai mock yang disetujui).
              Center(
                child: Image.asset(
                  'assets/images/logo_bpr.png',
                  width: 300,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _title.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 54,
                  fontWeight: FontWeight.w900,
                  color: AppColors.gold,
                  letterSpacing: 4,
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.gold.withValues(alpha: 0),
                      AppColors.gold,
                      AppColors.gold.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo "hidup": glow bernapas + scale halus,
                            // loop 4 detik (versi native dari logo-bpr-loop).
                            PulsingLogo(width: 560),
                            SizedBox(height: 40),
                            WaitingDots(),
                          ],
                        ),
                      )
                    : LayoutBuilder(
                        builder: (ctx, constraints) {
                          final n = shown.length;
                          const gap = 12.0;
                          // Kartu dibatasi tingginya agar tidak melar jadi
                          // raksasa saat nomor sedikit (1 nomor = hero).
                          final maxCardH = n == 1 ? 280.0 : 190.0;
                          // Bagi rata ruang yang ada, tapi tidak melebihi
                          // batas — selalu muat tanpa overflow.
                          final cardH =
                              ((constraints.maxHeight - gap * (n - 1)) / n)
                                  .clamp(0.0, maxCardH);
                          final fontSize =
                              (cardH * 0.5).clamp(18.0, 150.0);
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < n; i++) ...[
                                if (i > 0) const SizedBox(height: gap),
                                // Kartu dibatasi lebarnya (maks 1050px) dan
                                // ditengahkan — sesuai mock, tidak melar
                                // penuh selebar layar.
                                Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: 1050,
                                      minHeight: cardH,
                                      maxHeight: cardH,
                                    ),
                                    child: _numberCard(
                                      seq: i + 1,
                                      nomor: shown[i],
                                      fontSize: fontSize,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numberCard({
    required int seq,
    required String nomor,
    required double fontSize,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              seq.toString().padLeft(2, '0'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.bg,
              ),
            ),
          ),
          Expanded(
            child: Text(
              nomor,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Courier New', 'monospace'],
                letterSpacing: 6,
              ),
            ),
          ),
          const SizedBox(width: 60), // penyeimbang badge kiri
        ],
      ),
    );
  }
}

/// Logo BPR yang "hidup": glow bernapas + scale halus, loop 4 detik mulus.
/// Versi native Flutter dari `logo-bpr-loop` yang dibuat untuk overlay OBS —
/// dipakai di layar penonton (waiting state) dan header.
class PulsingLogo extends StatefulWidget {
  final double width;
  const PulsingLogo({super.key, required this.width});

  @override
  State<PulsingLogo> createState() => _PulsingLogoState();
}

class _PulsingLogoState extends State<PulsingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final breathe = 0.5 - 0.5 * math.cos(2 * math.pi * _c.value);
        return Transform.scale(
          scale: 1.0 + 0.024 * breathe,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: 0.35 + 0.30 * breathe,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Image.asset(
                    'assets/images/logo_bpr.png',
                    width: widget.width,
                  ),
                ),
              ),
              Image.asset('assets/images/logo_bpr.png', width: widget.width),
            ],
          ),
        );
      },
    );
  }
}

/// Teks "MENUNGGU PENGUNDIAN" dengan titik-titik animasi jalan.
class WaitingDots extends StatefulWidget {
  const WaitingDots({super.key});

  @override
  State<WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<WaitingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final n = (_c.value * 4).floor() % 4;
        // FittedBox: mengecil otomatis di layar sempit agar tidak overflow.
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'MENUNGGU PENGUNDIAN',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                  letterSpacing: 8,
                ),
              ),
              // Lebar tetap agar teks tidak goyang saat titik berubah.
              SizedBox(
                width: 76,
                child: Text(
                  '.' * n,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w600,
                    color: AppColors.gold,
                    letterSpacing: 8,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

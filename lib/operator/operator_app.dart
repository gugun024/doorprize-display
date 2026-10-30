import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/database.dart';
import '../shared/protocol.dart';
import '../shared/theme.dart';

class OperatorApp extends StatelessWidget {
  const OperatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doorprize Display - Operator',
      theme: buildTheme(),
      debugShowCheckedModeBanner: false,
      home: const OperatorScreen(),
    );
  }
}

class OperatorScreen extends StatefulWidget {
  const OperatorScreen({super.key});

  @override
  State<OperatorScreen> createState() => _OperatorScreenState();
}

class _OperatorScreenState extends State<OperatorScreen> {
  final _inputCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  Timer? _titleDebounce;
  Round? _round;
  List<DoorprizeNumber> _numbers = [];
  List<Round> _history = [];
  final Map<int, List<DoorprizeNumber>> _historyNumbers = {};
  final Set<int> _expanded = {};
  bool _loading = true;
  bool _openingAudience = false;
  bool _audienceOpen = false;
  WindowController? _audienceController;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _titleDebounce?.cancel();
    _inputCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('Doorprize Display - Operator');
    await windowManager.setMinimumSize(const Size(760, 640));
    // Daftarkan operator di channel bidirectional (wajib — lihat
    // AudienceChannel.initReceiver) SEBELUM ada pengiriman ke penonton.
    await AudienceChannel.initReceiver((_, _) async {});
    // Judul di-load sekali di awal (jangan di _load, biar tidak menimpa
    // teks yang sedang diketik tiap ada perubahan nomor).
    _titleCtrl.text = await DatabaseHelper.instance.getSetting(
      DatabaseHelper.kTitle,
      DatabaseHelper.defaultTitle,
    );
    await _load();
    // CATATAN: window penonton TIDAK dibuka otomatis — user membukanya
    // sendiri lewat tombol TV di AppBar (keputusan user 2026-10-30).
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final round = await db.getOrCreateActiveRound();
    final numbers = await db.getNumbers(round.id!);
    final history = await db.getFinishedRounds();
    if (!mounted) return;
    setState(() {
      _round = round;
      _numbers = numbers;
      _history = history;
      _loading = false;
    });
    await _syncAudience();
  }

  /// Cari window penonton yang sudah ada (biar tidak dobel).
  Future<WindowController?> _findAudience() async {
    try {
      final all = await WindowController.getAll();
      for (final c in all) {
        if (c.arguments == 'audience') return c;
      }
    } catch (_) {}
    return null;
  }

  /// Toggle layar penonton: klik buka, klik lagi tutup.
  Future<void> _toggleAudience() async {
    if (_openingAudience) return;
    final controller = _audienceController;
    if (_audienceOpen && controller != null) {
      try {
        await controller.hide();
      } catch (_) {}
      AudienceChannel.enabled = false;
      if (mounted) {
        setState(() {
          _audienceOpen = false;
          _audienceController = null;
        });
      }
      return;
    }
    // State tidak sinkron (mis. penonton ditutup via tombol X di window-nya)
    // → reset lalu buka baru.
    if (mounted) {
      setState(() {
        _audienceOpen = false;
        _audienceController = null;
      });
    }
    AudienceChannel.enabled = false;
    await _openAudience();
  }

  Future<void> _openAudience() async {
    if (_openingAudience) return;
    if (mounted) setState(() => _openingAudience = true);
    try {
      var controller = await _findAudience();
      controller ??= await WindowController.create(
        const WindowConfiguration(arguments: 'audience'),
      );
      _audienceController = controller;
      await controller.show();
      AudienceChannel.enabled = true;
      if (mounted) setState(() => _audienceOpen = true);
      // Sinkronisasi awal. Diulang setelah jeda singkat karena engine
      // window penonton butuh waktu untuk registrasi handler channel-nya —
      // kiriman pertama bisa hilang kalau handler belum siap.
      await _syncAudience();
      await Future.delayed(const Duration(seconds: 1));
      await _syncAudience();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka layar penonton: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingAudience = false);
    }
  }

  /// Kirim state terbaru ke layar penonton.
  Future<void> _syncAudience() async {
    await AudienceChannel.send(DoorprizeProtocol.update, {
      DoorprizeProtocol.argTitle: _titleCtrl.text.trim().isEmpty
          ? DatabaseHelper.defaultTitle
          : _titleCtrl.text.trim(),
      DoorprizeProtocol.argNumbers: [for (final n in _numbers) n.nomor],
    });
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.danger : null,
      ),
    );
  }

  Future<void> _add() async {
    final round = _round;
    if (round == null) return;
    final nomor = _inputCtrl.text.trim();
    if (nomor.isEmpty) {
      _snack('Nomor tidak boleh kosong.', error: true);
      return;
    }
    try {
      await DatabaseHelper.instance.addNumber(round.id!, nomor);
    } on DuplicateNumberException {
      _snack('Nomor "$nomor" sudah ada di ronde ini.', error: true);
      return;
    }
    _inputCtrl.clear();
    await _load();
  }

  Future<void> _edit(DoorprizeNumber n) async {
    final round = _round;
    if (round == null) return;
    final ctrl = TextEditingController(text: n.nomor);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Edit Nomor'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nomor'),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || result == n.nomor) return;
    try {
      await DatabaseHelper.instance.updateNumber(n.id!, round.id!, result);
    } on DuplicateNumberException {
      _snack('Nomor "$result" sudah ada di ronde ini.', error: true);
      return;
    }
    await _load();
  }

  Future<void> _delete(DoorprizeNumber n) async {
    await DatabaseHelper.instance.deleteNumber(n.id!);
    await _load();
  }

  /// Selesaikan ronde aktif → masuk riwayat, mulai ronde baru yang kosong.
  Future<void> _finishRound() async {
    final round = _round;
    if (round == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Selesaikan Ronde?'),
        content: Text(
          '${round.nama} (${_numbers.length} nomor) akan disimpan ke riwayat '
          'dan layar penonton dikosongkan untuk ronde berikutnya.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseHelper.instance.finishRound(round.id!);
      _expanded.clear();
      _historyNumbers.clear();
      await _load();
      _snack('${round.nama} tersimpan di riwayat.');
    }
  }

  /// Judul disimpan otomatis (debounce) + langsung tampil di penonton.
  void _onTitleChanged(String _) {
    _titleDebounce?.cancel();
    _titleDebounce = Timer(const Duration(milliseconds: 600), _saveTitle);
  }

  Future<void> _saveTitle() async {
    final t = _titleCtrl.text.trim();
    await DatabaseHelper.instance.setSetting(
      DatabaseHelper.kTitle,
      t.isEmpty ? DatabaseHelper.defaultTitle : t,
    );
    await _syncAudience();
  }

  Future<void> _toggleHistory(Round r) async {
    final id = r.id!;
    if (_expanded.contains(id)) {
      setState(() => _expanded.remove(id));
      return;
    }
    final numbers = await DatabaseHelper.instance.getNumbers(id);
    if (!mounted) return;
    setState(() {
      _expanded.add(id);
      _historyNumbers[id] = numbers;
    });
  }

  Future<void> _deleteHistoryRound(Round r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Hapus Riwayat?'),
        content: Text(
          '${r.nama} beserta nomor-nomornya akan dihapus permanen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text(
              'Hapus',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseHelper.instance.deleteRound(r.id!);
      _expanded.remove(r.id);
      _historyNumbers.remove(r.id);
      await _load();
    }
  }

  String _fmtTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${p2(d.day)}/${p2(d.month)}/${d.year} ${p2(d.hour)}:${p2(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Doorprize Display'),
          actions: [
            IconButton(
              icon: Icon(
                _audienceOpen ? Icons.tv : Icons.tv_off,
                color: _audienceOpen ? AppColors.success : AppColors.muted,
              ),
              tooltip: _audienceOpen
                  ? 'Tutup layar penonton'
                  : 'Buka layar penonton',
              onPressed: _toggleAudience,
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppColors.gold,
            labelColor: AppColors.gold,
            unselectedLabelColor: AppColors.muted,
            tabs: [
              const Tab(text: 'Ronde Aktif', icon: Icon(Icons.playlist_add)),
              Tab(
                text: 'Riwayat (${_history.length})',
                icon: const Icon(Icons.history),
              ),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _activeTab(),
                  _historyTab(),
                ],
              ),
      ),
    );
  }

  Widget _activeTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Kartu header ronde
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'RONDE AKTIF',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 2,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _round?.nama ?? '…',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.gold,
                        ),
                      ),
                      Text(
                        '${_numbers.length} nomor terdaftar',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _finishRound,
                  icon: const Icon(Icons.check),
                  label: const Text('Selesaikan Ronde'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Input nomor
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(
                    labelText: 'Nomor doorprize',
                    hintText: 'Contoh: 012345 — Enter untuk tambah',
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Tambah'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Judul layar (live)
          TextField(
            controller: _titleCtrl,
            onChanged: _onTitleChanged,
            decoration: const InputDecoration(
              labelText: 'Judul layar penonton',
              hintText: 'Otomatis tersimpan & tampil saat mengetik',
              prefixIcon: Icon(Icons.title),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 8),
          const SizedBox(height: 4),
          // Daftar nomor
          Expanded(
            child: _numbers.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.confirmation_number_outlined,
                          size: 48,
                          color: AppColors.muted,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Belum ada nomor di ronde ini.\nKetik nomor di atas lalu tekan Enter.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _numbers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final n = _numbers[i];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text(
                                (i + 1).toString().padLeft(2, '0'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                n.nomor,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace',
                                  fontFamilyFallback: [
                                    'Courier New',
                                    'monospace'
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  color: AppColors.muted),
                              tooltip: 'Edit',
                              onPressed: () => _edit(n),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppColors.danger),
                              tooltip: 'Hapus',
                              onPressed: () => _delete(n),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _historyTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: _history.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history,
                    size: 48,
                    color: AppColors.muted,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Belum ada ronde yang selesai.\nRonde yang diselesaikan akan tersimpan di sini.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: _history.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final r = _history[i];
                final isOpen = _expanded.contains(r.id);
                final nums = _historyNumbers[r.id] ?? const [];
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        title: Text(
                          r.nama,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        subtitle: Text(
                          _fmtTime(r.finishedAt ?? r.createdAt),
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppColors.danger),
                              tooltip: 'Hapus riwayat',
                              onPressed: () => _deleteHistoryRound(r),
                            ),
                            Icon(isOpen
                                ? Icons.expand_less
                                : Icons.expand_more),
                          ],
                        ),
                        onTap: () => _toggleHistory(r),
                      ),
                      if (isOpen)
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: nums.isEmpty
                              ? const Text(
                                  'Tidak ada nomor.',
                                  style:
                                      TextStyle(color: AppColors.muted),
                                )
                              : Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (var j = 0; j < nums.length; j++)
                                      Chip(
                                        label: Text(
                                          '${(j + 1).toString().padLeft(2, '0')}. ${nums[j].nomor}',
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 14,
                                          ),
                                        ),
                                        backgroundColor: AppColors.card,
                                        side: const BorderSide(
                                            color: AppColors.border),
                                      ),
                                  ],
                                ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

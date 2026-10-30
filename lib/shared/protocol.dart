import 'package:desktop_multi_window/desktop_multi_window.dart';

/// Protokol komunikasi operator → penonton via WindowMethodChannel
/// 'doorprize_audience' (satu arah: operator invoke, penonton handle).
class DoorprizeProtocol {
  DoorprizeProtocol._();

  static const String channelName = 'doorprize_audience';

  /// Tampilkan daftar nomor terbaru di layar penonton.
  /// args: `{title: String, numbers: List<String>}`
  static const String update = 'update';

  static const String argTitle = 'title';
  static const String argNumbers = 'numbers';
}

/// Pengirim perintah ke window penonton (dipakai window operator).
class AudienceChannel {
  AudienceChannel._();

  static final _channel = WindowMethodChannel(
    DoorprizeProtocol.channelName,
    mode: ChannelMode.bidirectional,
  );

  /// Nyalakan setelah window penonton berhasil dibuka.
  static bool enabled = false;

  /// WAJIB dipanggil sekali saat window operator mulai.
  /// Mendaftarkan operator sebagai handler di channel bidirectional —
  /// tanpa ini native menganggap operator bukan bagian dari pasangan
  /// sehingga SEMUA invokeMethod dari operator gagal diam-diam.
  /// (Pola yang sama dipakai aplikasi undian.)
  static Future<void> initReceiver(
      Future<void> Function(String method, Map? args) onMessage) async {
    try {
      await _channel.setMethodCallHandler((call) async {
        final args = (call.arguments as Map?)?.cast<String, Object?>();
        await onMessage(call.method, args);
      });
    } catch (_) {
      // Gagal registrasi — pengiriman ke penonton tetap dicoba.
    }
  }

  static Future<void> send(String method, [Map<String, Object?>? args]) async {
    if (!enabled) return;
    try {
      await _channel.invokeMethod(method, args);
    } catch (_) {
      // window penonton belum siap / sudah ditutup — abaikan
    }
  }
}

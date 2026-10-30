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

  static final _channel = WindowMethodChannel(DoorprizeProtocol.channelName);

  /// Nyalakan setelah window penonton berhasil dibuka.
  static bool enabled = false;

  static Future<void> send(String method, [Map<String, Object?>? args]) async {
    if (!enabled) return;
    try {
      await _channel.invokeMethod(method, args);
    } catch (_) {
      // window penonton belum siap / sudah ditutup — abaikan
    }
  }
}

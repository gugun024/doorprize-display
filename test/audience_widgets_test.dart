import 'package:doorprize_display/audience/audience_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PulsingLogo tampil dan animasinya jalan', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PulsingLogo(width: 300)),
      ),
    );
    expect(find.byType(PulsingLogo), findsOneWidget);
    // Majukan beberapa frame animasi (loop 4 detik) — pastikan builder
    // tidak throw saat phase berubah.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(PulsingLogo), findsOneWidget);
  });

  testWidgets('WaitingDots menampilkan teks + titik animasi', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WaitingDots()),
      ),
    );
    expect(find.textContaining('MENUNGGU PENGUNDIAN'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.textContaining('MENUNGGU PENGUNDIAN'), findsOneWidget);
  });
}

// TEMPORARY generator, not a test of behaviour.
//
// Renders the app's own brand mark to PNGs used as launcher-icon sources, so
// the icon is the same wallet-on-blue as the login screen rather than unrelated
// artwork. Run with:
//   flutter test test/tool_generate_icon_test.dart --update-goldens
//
// Outputs (into assets/icon/):
//   app_icon.png            1024² full-bleed — legacy launcher icon, web, etc.
//   app_icon_foreground.png 1024² transparent — Android adaptive foreground,
//                           art kept inside the centre safe zone.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

const _deep = Color(0xFF104281); // blue ramp 650
const _mid = Color(0xFF1C5CAB); // blue ramp 550

final _iconFont = File(
  r'C:\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
);

/// Only this machine's SDK path is known, so elsewhere the generator sits out
/// rather than failing a run it has nothing to do with. (testWidgets takes a
/// bool here, not a reason string.)
final _skip = !_iconFont.existsSync();

Future<void> _loadIconFont() async {
  if (_skip) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(
      _iconFont.readAsBytes().then(
        (b) => ByteData.sublistView(Uint8List.fromList(b)),
      ),
    );
  await loader.load();
}

/// 1024 logical pixels at dpr 1 = a 1024x1024 PNG.
Future<void> _sized(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1024, 1024);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(1024, 1024)),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadIconFont);

  testWidgets('generate: full icon', (tester) async {
    await _sized(
      tester,
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_mid, _deep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.account_balance_wallet_rounded,
            size: 560,
            color: Colors.white,
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(DecoratedBox).first,
      matchesGoldenFile('../assets/icon/app_icon.png'),
    );
  }, skip: _skip);

  testWidgets('generate: adaptive foreground', (tester) async {
    // Android masks adaptive icons hard: only the centre ~66/108 of the canvas
    // is guaranteed visible, so the glyph is kept well inside it.
    await _sized(
      tester,
      const SizedBox(
        width: 1024,
        height: 1024,
        child: Center(
          child: Icon(
            Icons.account_balance_wallet_rounded,
            size: 430,
            color: Colors.white,
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(SizedBox).first,
      matchesGoldenFile('../assets/icon/app_icon_foreground.png'),
    );
  }, skip: _skip);
}

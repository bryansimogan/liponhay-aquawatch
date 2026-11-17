import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fish_farm_app/widgets/aquatic_scene.dart';

void main() {
  testWidgets('pond fits a small phone and can rotate', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: AquaticBackground(
      child: Scaffold(backgroundColor: Colors.transparent, body: PondScene()),
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Drag to explore your pond'), findsOneWidget);
    await tester.dragFrom(const Offset(160, 100), const Offset(50, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

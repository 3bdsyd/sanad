import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snad/features/ads/presentation/ad_separated_content.dart';

void main() {
  testWidgets('banner band is empty while jobs paint behind navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundaryKey = GlobalKey();
    var jobTaps = 0;
    var bannerTaps = 0;
    var banner = 140.0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              extendBody: true,
              body: RepaintBoundary(
                key: boundaryKey,
                child: AdSeparatedContent(
                  bannerExtent: banner,
                  child: GestureDetector(
                    onTap: () => jobTaps++,
                    child: const ColoredBox(
                      color: Colors.red,
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              bottomNavigationBar: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (banner > 0)
                    GestureDetector(
                      onTap: () => bannerTaps++,
                      child: SizedBox(
                        height: banner,
                        width: double.infinity,
                        child: const ColoredBox(color: Colors.blue),
                      ),
                    ),
                  const SizedBox(height: 80),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    expect(boundary.size, const Size(300, 600));
    final pixels = (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data;
    }))!;
    int alphaAt(int y) => pixels.getUint8((y * 300 + 150) * 4 + 3);
    expect(alphaAt(100), 255);
    expect(
      alphaAt(450),
      0,
      reason: 'No job content may paint in the banner band.',
    );
    expect(
      alphaAt(560),
      255,
      reason: 'The navigation glass needs the live job backdrop.',
    );
    await tester.tapAt(const Offset(150, 100));
    await tester.tapAt(const Offset(150, 450));
    await tester.tapAt(const Offset(150, 560));
    expect(jobTaps, 1, reason: 'Banner and navigation must not activate jobs.');
    expect(bannerTaps, 1);

    update(() => banner = 0);
    await tester.pump();
    await tester.tapAt(const Offset(150, 450));
    expect(
      jobTaps,
      2,
      reason: 'Removing the banner restores the entire viewport.',
    );
    expect(tester.takeException(), isNull);
  });
}

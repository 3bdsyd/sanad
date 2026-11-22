import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Keeps browser chrome and Safari's sampled header edge on Sanad colors.
class WebBrowserChrome {
  WebBrowserChrome._();

  static final _bottomInset = ValueNotifier<double>(0);
  static web.EventListener? _viewportListener;

  static void _readViewport() {
    final inset = double.tryParse(
      web.document.documentElement?.getAttribute('data-sanad-bottom-inset') ??
          '',
    );
    if (inset != null) _bottomInset.value = inset;
  }

  /// Scrolling content can paint beneath Safari; fixed controls use SafeArea.
  static Widget wrap(Widget child) => ValueListenableBuilder<double>(
    valueListenable: _bottomInset,
    child: child,
    builder: (context, bottom, child) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
          padding: media.padding.copyWith(bottom: bottom),
          viewPadding: media.viewPadding.copyWith(bottom: bottom),
        ),
        child: child!,
      );
    },
  );

  /// Sync Safari/Chrome toolbar colors with the active Sanad surface.
  static void apply({required bool isDark, required String headerColor}) {
    final color = headerColor;
    if (_viewportListener == null) {
      _readViewport();
      _viewportListener = ((web.Event _) => _readViewport()).toJS;
      web.window.addEventListener('sanad-viewport-change', _viewportListener);
    }
    final document = web.document;
    final metas = document.querySelectorAll('meta[name="theme-color"]');
    for (var i = 0; i < metas.length; i++) {
      final node = metas.item(i);
      if (node == null) continue;
      final meta = node as web.HTMLMetaElement;
      if (i > 0) {
        meta.remove();
        continue;
      }
      meta.content = color;
      // Drop media so the in-app choice wins over prefers-color-scheme.
      meta.removeAttribute('media');
    }
    final scheme = isDark ? 'dark' : 'light';
    final schemeMeta =
        document.querySelector('meta[name="color-scheme"]')
            as web.HTMLMetaElement?;
    schemeMeta?.content = scheme;
    if (metas.length == 0) {
      final meta = document.createElement('meta') as web.HTMLMetaElement;
      meta.name = 'theme-color';
      meta.content = color;
      document.head?.append(meta);
    }
    final root = document.documentElement;
    if (root != null) {
      final html = root as web.HTMLElement;
      html.setAttribute('data-sanad-theme', scheme);
      html.style.setProperty('color-scheme', scheme);
      html.style.setProperty('--sanad-header-color', color);
      html.style.backgroundColor = color;
    }
    final body = document.body;
    if (body != null) {
      body.style.setProperty('color-scheme', scheme);
      body.style.backgroundColor = color;
    }
  }
}

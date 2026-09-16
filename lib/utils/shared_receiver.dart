import 'dart:io' show Platform;

import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:jni/jni.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

final _urlRegExp = RegExp(
  r'https?://[^\s<>"`\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]+',
  caseSensitive: false,
);

abstract final class SharedReceiver {
  static bool _initialised = false;

  static void init() {
    if (_initialised) return;
    _initialised = true;
    if (!Platform.isAndroid) return;
    AndroidHelper$ToDart.onSharedText = Runnable.implement(
      $Runnable(run: _onSharedText),
    );
    _checkPending();
  }

  static void _onSharedText() {
    _checkPending();
  }

  static void _checkPending() {
    if (!Platform.isAndroid) return;
    try {
      final jstr = AndroidHelper.pendingSharedText;
      if (jstr == null) return;
      final text = jstr.toDartString(releaseOriginal: true);
      AndroidHelper.pendingSharedText = null;
      _handleText(text);
    } catch (_) {}
  }

  static void _handleText(String text) {
    final match = _urlRegExp.firstMatch(text);
    if (match != null) {
      final url = match.group(0)!;
      PiliScheme.routePushFromUrl(url);
    } else {
      if (Get.context != null) {
        SmartDialog.showToast('未识别链接');
      }
    }
  }

  static void dispose() {
    _initialised = false;
    if (!Platform.isAndroid) return;
    try {
      AndroidHelper$ToDart.onSharedText?.release();
      AndroidHelper$ToDart.onSharedText = null;
    } catch (_) {}
  }
}

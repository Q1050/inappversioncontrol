import 'dart:io' show Platform;

import '../models.dart';

AppPlatform getCurrentAppPlatform() {
  if (Platform.isAndroid) {
    return AppPlatform.android;
  }
  if (Platform.isIOS) {
    return AppPlatform.ios;
  }
  if (Platform.isMacOS) {
    return AppPlatform.macos;
  }
  if (Platform.isWindows) {
    return AppPlatform.windows;
  }
  if (Platform.isLinux) {
    return AppPlatform.linux;
  }

  throw UnsupportedError(
    'Unsupported IO platform for automatic app platform detection.',
  );
}

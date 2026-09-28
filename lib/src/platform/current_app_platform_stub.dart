import '../models.dart';

AppPlatform getCurrentAppPlatform() {
  throw UnsupportedError(
    'Automatic platform detection is not supported on this platform. '
    'Pass an AppPlatform explicitly.',
  );
}

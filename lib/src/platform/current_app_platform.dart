import '../models.dart';
import 'current_app_platform_stub.dart'
    if (dart.library.io) 'current_app_platform_io.dart'
    if (dart.library.js_interop) 'current_app_platform_web.dart';

AppPlatform currentAppPlatform() => getCurrentAppPlatform();

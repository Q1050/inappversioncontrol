`in_app_version_control` is a Flutter/Dart package for backend-driven app
version governance. It fetches a version rule from your backend and decides
whether the app should continue normally, suggest an update, force an update,
or enter maintenance mode.

## Features

- Backend-agnostic decision engine
- Optional update, forced update, and maintenance mode support
- Pluggable provider interface for Firebase Remote Config or custom servers
- Built-in endpoint provider for teams that already expose their own backend API
- Enum-backed backend source selection through provider types

## Install in a Flutter project

Install the latest published version from pub.dev:

```bash
flutter pub add in_app_version_control
```

Or add the dependency to the consuming app's `pubspec.yaml`:

```yaml
dependencies:
  in_app_version_control: ^0.0.4
```

Then install dependencies:

```bash
flutter pub get
```

Import the public package API wherever version checks are needed:

```dart
import 'package:in_app_version_control/in_app_version_control.dart';
```

For Firebase Remote Config, also add Firebase Core and configure Firebase for
the consuming app. Firebase configuration files are intentionally not included
in this repository because every app must use its own Firebase project.

```bash
flutter pub add firebase_core
dart pub global activate flutterfire_cli
flutterfire configure
```

Initialize Firebase before creating a `FirebaseVersionRuleProvider`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}
```

## Getting started

Create a `VersionRuleProvider`, pass it to `InAppVersionControl`, and call
`check()` with your app ID and current version. The package can infer the
current runtime platform automatically, or you can override it manually.

Use the built-in platform enum values instead of raw strings:

- `AppPlatform.android`
- `AppPlatform.ios`
- `AppPlatform.web`
- `AppPlatform.macos`
- `AppPlatform.windows`
- `AppPlatform.linux`

Backend source is a separate enum exposed by each provider:

- `BackendService.firebase`
- `BackendService.custom`

Rules can be separated by deployment environment:

- `AppEnvironment.production` (default)
- `AppEnvironment.staging`
- `AppEnvironment.testing`
- `AppEnvironment.development`

The default version format is numeric dot-separated strings such as:

- `1`
- `1.2`
- `1.2.3`

Non-numeric segments such as `1.2.0-beta` are rejected by design.

## Usage

### 1. Use a custom provider

```dart
import 'package:in_app_version_control/in_app_version_control.dart';

class MyBackendProvider implements VersionRuleProvider {
  @override
  BackendService get backendService => BackendService.custom;

  @override
  Future<VersionRule> fetchRule({
    required String appId,
    required AppPlatform platform,
  }) async {
    // Call your existing backend here.
    return const VersionRule(
      minVersion: '1.4.0',
      latestVersion: '1.6.0',
      storeUrl: 'https://example.com/store',
      message: 'A newer version is available.',
    );
  }
}

final versionControl = InAppVersionControl(
  provider: MyBackendProvider(),
);

final decision = await versionControl.check(
  appId: 'com.example.app',
  currentVersion: '1.5.0',
);
```

### Recheck after the app resumes

Lifecycle-aware checking is opt-in. Create a `VersionControlLifecycle`, start
it once from the owning component, listen for state changes, and dispose it
with that component:

```dart
late final VersionControlLifecycle lifecycle;

@override
void initState() {
  super.initState();
  lifecycle = VersionControlLifecycle(
    versionControl: versionControl,
    appId: 'com.example.app',
    currentVersion: '1.1.0',
  )..addListener(_handlePolicyChange);
  lifecycle.start();
}

void _handlePolicyChange() {
  final decision = lifecycle.decision;
  final error = lifecycle.error;
  // Update your dialog, route, or blocking UI from this state.
}

@override
void dispose() {
  lifecycle.dispose();
  super.dispose();
}
```

By default, the coordinator checks once on `start()`, then checks once after
each genuine foreground departure followed by `AppLifecycleState.resumed`.
The initial `resumed` event, repeated `resumed` events, temporary `inactive`
events, and widget rebuilds do not trigger checks. Set `checkInitially` or
`checkOnResume` to `false` to disable either behavior.

Checks never overlap. If a resume occurs during a check, duplicate requests
are coalesced into one pending check. A refresh failure is exposed through
`error`, while the last successful `decision` remains available so a known
force-update or maintenance state is not accidentally removed. A cold-start
failure has an error and no decision.

The lifecycle coordinator requests evaluations only. It does not poll, run in
the background, or override provider caching and minimum-fetch intervals.

### 2. Use the built-in endpoint provider

This is the easiest path if you already have a backend endpoint and only need
the package to call it.

```dart
import 'package:in_app_version_control/in_app_version_control.dart';

final provider = EndpointVersionRuleProvider(
  endpoint: Uri.parse('https://api.example.com/mobile/version-rule'),
  method: EndpointRequestMethod.post,
  headers: const {
    'x-api-key': 'your-api-key',
  },
);

final versionControl = InAppVersionControl(provider: provider);

final decision = await versionControl.check(
  appId: 'com.example.app',
  currentVersion: '1.1.0',
);
```

The default endpoint payload is:

```json
{
  "appId": "com.example.app",
  "platform": "ios",
  "environment": "production"
}
```

The default endpoint response shape is:

```json
{
  "minVersion": "1.0.0",
  "latestVersion": "1.2.0",
  "storeUrl": "https://example.com/store",
  "message": "Update available",
  "maintenance": false
}
```

### 3. Map an existing backend response

If your endpoint already returns a different JSON shape, provide a custom
`ruleBuilder` and keep your existing backend contract.

```dart
final provider = EndpointVersionRuleProvider(
  endpoint: Uri.parse('https://api.example.com/version-policy'),
  method: EndpointRequestMethod.get,
  ruleBuilder: (json, context) {
    final data = json['data'] as Map<String, dynamic>;
    return VersionRule(
      minVersion: data['min_version'] as String,
      latestVersion: data['latest_version'] as String,
      storeUrl: data['store_url'] as String?,
      message: data['notice'] as String?,
      maintenance: data['is_maintenance'] as bool? ?? false,
    );
  },
);
```

### 4. Use Firebase Remote Config

Configure the consuming app with FlutterFire and initialize Firebase before
creating the provider:

```dart
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);

final versionControl = InAppVersionControl(
  environment: AppEnvironment.production,
  provider: FirebaseVersionRuleProvider.remoteConfig(
    environmentKeys: {
      AppEnvironment.production: {
        AppPlatform.android: 'version_rule_android_production',
        AppPlatform.ios: 'version_rule_ios_production',
      },
      AppEnvironment.testing: {
        AppPlatform.android: 'version_rule_android_testing',
        AppPlatform.ios: 'version_rule_ios_testing',
      },
    },
  ),
);

final decision = await versionControl.check(
  appId: 'com.example.app',
  environment: AppEnvironment.testing,
  currentVersion: '1.1.0',
);
```

Each Remote Config key should store a JSON rule payload like:

```json
{
  "minVersion": "1.0.0",
  "latestVersion": "1.2.0",
  "storeUrl": "https://example.com/store",
  "message": "Update available",
  "maintenance": false,
  "supportedPlatforms": ["android", "ios"]
}
```

### 5. Restrict rules to specific runtimes

If a rule should only apply to certain app runtimes, set
`supportedPlatforms`:

```dart
const rule = VersionRule(
  minVersion: '1.0.0',
  latestVersion: '1.2.0',
  supportedPlatforms: {AppPlatform.android, AppPlatform.ios},
);
```

### 6. Inspect the provider backend type

```dart
final backend = versionControl.backendService;

if (backend == BackendService.custom) {
  // Use custom endpoint behavior.
}
```

## Decision rules

- `maintenance == true` returns `UpdateType.maintenance`
- `currentVersion < minVersion` returns `UpdateType.force`
- `currentVersion < latestVersion` returns `UpdateType.optional`
- Otherwise, `UpdateType.none`

## Example app

An interactive Flutter demo is included in [example/](./example). It lets you
switch between update scenarios and app platforms so you can verify the package
behavior before publishing.

## CLI

The package now includes an `iavc` executable for onboarding and validation.

Run it with Flutter:

```bash
dart run in_app_version_control:iavc --help
```

Available commands:

```bash
dart run in_app_version_control:iavc rule:validate path/to/rule.json
dart run in_app_version_control:iavc endpoint:test https://api.example.com/version-rule --method post --platform android
dart run in_app_version_control:iavc app:firebase configure --mode remote-config
dart run in_app_version_control:iavc app:firebase configure --project your-project-id --android-package com.example.app --write-alias default --deploy-remoteconfig true
dart run in_app_version_control:iavc app:custom configure --method post
```

When run from a configured Flutter project, `app:firebase configure`
automatically reads the Firebase project ID from `.firebaserc` or a
FlutterFire-generated `firebase.json`. It also reads the Android package name
from `android/app/build.gradle.kts` or `android/app/build.gradle`. Use
`--project` or `--android-package` only when detection is unavailable or you
want to override it.

# Example

Run this example app from the package root:

```bash
cd example
flutter pub get
flutter run
```

It demonstrates:

- `UpdateType.none`
- `UpdateType.optional`
- `UpdateType.force`
- `UpdateType.maintenance`
- in-memory provider flow
- Firebase Remote Config provider flow with a mocked Remote Config client
- opt-in lifecycle rechecking after a genuine foreground resume

The example uses the real `FirebaseVersionRuleProvider` API with a local mock
client, so it runs without Firebase credentials. Follow the package README to
connect a consuming application to its own Firebase project.

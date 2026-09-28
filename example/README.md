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
- live Firebase Remote Config flow
- Firebase Remote Config provider flow with a mocked Remote Config client

The live Firebase mode is configured for the Android app `com.example.app` in
the `chatapp-c5dfa` Firebase project. It reads separate production, staging,
testing, and development rules. The mock mode remains available for changing
decision scenarios locally without modifying Remote Config.

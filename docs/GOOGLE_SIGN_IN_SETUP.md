# Google Sign-In configuration

The UI contains a **Continue with Google** button. It is disabled when OAuth
is not configured, rather than pretending to authenticate.

1. In Google Cloud Console, configure an OAuth consent screen for the app.
2. Register the Android package: `com.jahid.droidreai`.
3. Register SHA-1/SHA-256 fingerprints for the relevant debug and signing keys.
4. Create the appropriate web/server OAuth client ID for Google identity.
5. Launch the app with:

```bash
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_OAUTH_CLIENT_ID
```

6. For GitHub builds, pass the configured client ID via a protected build
   secret or deliberately non-sensitive repository variable; never commit
   OAuth client secrets or private credentials.

The code uses `google_sign_in` and displays the user's identity after
the Google authentication flow. **This is not yet a production server-backed
session.** Before enabling cloud account syncing, verify Google ID tokens
on a trusted server or integrate Firebase Authentication and validate access
through backend security rules.

Google Sign-In does not grant access to paid AI providers or Gmail inbox data.

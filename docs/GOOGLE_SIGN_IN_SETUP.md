# Google Sign-In configuration

The **Account & Settings** page now lets you save a Web OAuth Client ID on the
device and offers **Continue with Google**. The ID is public client metadata,
not an API secret. The application does not request Gmail mailbox access.

1. In Google Cloud Console, configure the consent screen and add your account
   as a test user if the app remains in testing.
2. Create an **Android OAuth Client** with package `com.jahid.droidreai` and
   the **SHA-1 of the certificate actually signing the APK**. Verify a built
   APK using Android SDK Build Tools, for example:

   ```bash
   apksigner verify --print-certs path/to/app-debug.apk
   ```

3. Create a separate **Web application OAuth Client ID** in the same Google
   Cloud project. This is the `serverClientId` required by the Flutter plugin
   when `google-services.json` is not used.
4. Open the app → **Account & Settings** → enter the **Web OAuth Client ID** →
   tap **Save OAuth configuration**, then **Continue with Google**. If you
   previously authenticated using a different Client ID, restart the app.
5. Alternatively, embed a public default ID at build time:

```bash
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_OAUTH_CLIENT_ID
```

6. For GitHub builds, you may pass the ID via a repository variable and
   `--dart-define`; the Settings entry is sufficient without modifying CI.
   Never commit OAuth client **secrets**, ID tokens or keystore passwords.

**Important for GitHub Actions:** the current debug workflow uses the runner's
default debug signing key, which may differ between workflow runs. An Android
OAuth Client registered with one APK's signing SHA may fail for another APK.
For reliable distributable builds, sign using an owner-controlled stable
keystore (configured securely outside source control), register its SHA in
Google Cloud, and use that same signing identity for every build. This app
does **not** bypass or auto-register Google OAuth certificate restrictions.

The code uses `google_sign_in` and displays the user's identity after a valid
Google authentication flow. It tries a lightweight restore for returning
users. **This is not yet a production server-backed session.** Before enabling
cloud account syncing, verify Google ID tokens on a trusted server or
integrate Firebase Authentication and validate access via backend rules.

Google Sign-In does not grant access to paid AI providers or Gmail inbox data.

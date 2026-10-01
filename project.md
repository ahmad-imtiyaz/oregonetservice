# Project Documentation: Oregonet Service

## Overview

**Oregonet Service** is a Flutter WebView wrapper application for the web app at `https://oregonetservice.my.id/`. It provides a native mobile experience (Android, iOS, Web, Windows, Linux, macOS) with additional features like file upload support, push notifications (FCM), WhatsApp link handling, and custom pull-to-refresh.

---

## Project Structure

```
oregonetservice/
├── lib/
│   ├── main.dart              # Entry point + WebView logic (core)
│   ├── push_notifications.dart # FCM + local notifications
│   └── whatsapp_link.dart      # WhatsApp link detection & handling
├── android/                    # Android native config
├── ios/                        # iOS native config
├── web/                        # Web (PWA) config
├── linux/                      # Linux desktop config
├── macos/                      # macOS desktop config
├── windows/                    # Windows desktop config
├── assets/
│   └── images/logo.png         # App icon & splash source
├── pubspec.yaml                # Dependencies & build config
└── project.md                  # This file
```

---

## Key Files & Their Responsibilities

### `lib/main.dart` — Core Application Logic

**Location**: `lib/main.dart`  
**Purpose**: App entry point, WebView controller, file upload handling, pull-to-refresh, error UI.

**Key Constants**:
| Constant | Value | Description |
|----------|-------|-------------|
| `kHomeUrl` | `https://oregonetservice.my.id/` | Main web URL loaded in WebView |
| `kBrandColor` | `Color(0xFF8B0021)` | Brand color (from logo) |
| `kMaxUploadBytes` | `1,800 KB` | Max file size (server limit 2MB, margin kept) |

**Main Classes**:
- `OregonetServiceApp` — Root widget, MaterialApp setup
- `WebViewHomePage` — Stateful widget containing WebView logic
- `_WebViewHomePageState` — All WebView behavior lives here

**Key Features in `_WebViewHomePageState`**:

| Feature | Implementation |
|---------|----------------|
| **WebView Controller** | `_createController()` — Platform-specific (Android WKWebView / WebKit), JS unrestricted, background white |
| **Navigation Delegate** | Blocks external navigation except WhatsApp links; handles load/error/finish states |
| **File Upload (Android)** | `setOnShowFileSelector` → FilePicker (images only) → Compress (JPEG, progressive quality 80→65→50) → Convert to `content://` URI via FileProvider channel |
| **File Upload (iOS)** | Handled natively by WKWebView (requires `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` in Info.plist) |
| **Pull-to-Refresh** | Custom `Listener` tracking drag distance; triggers reload at 90px threshold; shows circular progress indicator |
| **Back Navigation** | `PopScope` + `_handleBack()`: WebView `goBack()` first, then exit confirmation dialog |
| **Error UI** | Full-screen overlay with retry button when main frame fails to load |
| **Loading Indicator** | Centered CircularProgressIndicator during initial load |

**Native Channel (Android)**:
```dart
MethodChannel('com.oregonetservice/fileprovider')
```
Used to convert local file paths to `content://` URIs so Chromium can read them.

---

### `lib/push_notifications.dart` — Firebase Cloud Messaging + Local Notifications

**Location**: `lib/push_notifications.dart`  
**Purpose**: Handle FCM token, foreground/background notifications, deep-link from notification tap.

**Constants**:
| Constant | Value | Description |
|----------|-------|-------------|
| `_kChannelId` | `tugas_baru` | Must match Laravel `FcmService.php` & AndroidManifest.xml |
| `_kChannelName` | `Tugas Baru` | Display name |
| `_kNotifIcon` | `ic_stat_oregonet` | Drawable resource (white vector icon) |

**Class: `PushNotifications`**

**Constructor**:
```dart
PushNotifications({
  required void Function(String token) onToken,
  required void Function(String path) onOpenPath,
})
```
- `onToken` — Called when FCM token obtained/refreshed; injects token into WebView via `injectFcmToken()`
- `onOpenPath` — Called when notification tapped; resolves path to full URL and navigates WebView

**`init()` Flow**:
1. `Firebase.initializeApp()`
2. Initialize `FlutterLocalNotificationsPlugin` with Android icon
3. Create notification channel `tugas_baru` (high importance, sound)
4. Request notification permission (Android 13+)
5. Listen to:
   - `FirebaseMessaging.onMessage` → `_showInForeground()` (show local notif when app open)
   - `FirebaseMessaging.onMessageOpenedApp` → `_openFromMessage()` (background tap)
   - `getInitialMessage()` → `_openFromMessage()` (terminated tap)
6. Get FCM token → `onToken(token)` + listen `onTokenRefresh`

**Helper Functions**:
- `injectFcmToken(controller, token)` — Injects token into WebView as `window.OREGONET_FCM_TOKEN` + dispatches `oregonet-fcm-token` CustomEvent
- `resolveAppPath(path, home)` — Validates path is same-host, returns full Uri or null

**Notification Payload Expected from Server (Laravel)**:
```json
{
  "notification": { "title": "...", "body": "..." },
  "data": { "path": "/worker/tasks/12" }
}
```

---

### `lib/whatsapp_link.dart` — WhatsApp Link Handling

**Location**: `lib/whatsapp_link.dart`  
**Purpose**: Detect WhatsApp URLs and open them externally.

**Functions**:
| Function | Description |
|----------|-------------|
| `isWhatsAppLink(Uri)` | Returns true for `whatsapp:` scheme, `wa.me`, `api.whatsapp.com`, `chat.whatsapp.com` hosts |
| `openExternally(Uri)` | Launches URL in external app; falls back to clipboard copy if launch fails |

**Integration**: Called from `NavigationDelegate.onNavigationRequest` in `main.dart` — prevents WebView navigation, opens externally.

---

## Platform-Specific Configuration

### Android (`android/app/src/main/`)

**AndroidManifest.xml**:
- Permissions: `INTERNET`, `CAMERA`, `POST_NOTIFICATIONS`, `READ_EXTERNAL_STORAGE` (API≤32), `READ_MEDIA_IMAGES/VIDEO` (API 33+)
- Firebase config: `default_notification_channel_id` = `tugas_baru`, `default_notification_icon` = `ic_stat_oregonet`
- Activity: `singleTop`, `adjustResize`, all configChanges
- **FileProvider**: `androidx.core.content.FileProvider`, authority `${applicationId}.fileprovider`, paths from `@xml/file_paths`

**file_paths.xml** (`res/xml/file_paths.xml`):
```xml
<cache-path name="cache_root" path="." />
```
Exposes entire cache directory for `content://` URIs.

**Notification Icon** (`res/drawable/ic_stat_oregonet.xml`):
White vector (24×24dp), transparent background — required for Android status bar icons.

**App Icon & Splash**: Generated via `flutter_launcher_icons` & `flutter_native_splash` from `assets/images/logo.png`.

---

### iOS (`ios/Runner/Info.plist`)

**Key Entries**:
| Key | Value |
|-----|-------|
| `CFBundleDisplayName` | `Oregonetservice` |
| `NSCameraUsageDescription` | "Aplikasi memerlukan akses kamera untuk mengambil foto pada formulir di website." |
| `NSPhotoLibraryUsageDescription` | "Aplikasi memerlukan akses galeri untuk memilih foto yang akan diunggah." |
| `NSMicrophoneUsageDescription` | "Aplikasi memerlukan akses mikrofon jika formulir memerlukan rekaman suara/video." |
| `UISupportedInterfaceOrientations` | Portrait, LandscapeLeft, LandscapeRight |

**Note**: No explicit Firebase config in Info.plist — handled via `GoogleService-Info.plist` (not in repo, must be added manually).

---

### Web (`web/`)

**index.html**: Standard Flutter web bootstrap with custom splash screen (light/dark mode images in `web/splash/img/`).

**manifest.json**: PWA manifest — standalone display, theme color `#0175C2`, icons from `web/icons/`.

---

## Dependencies (from `pubspec.yaml`)

### Runtime Dependencies
| Package | Version | Purpose |
|---------|---------|---------|
| `flutter` | SDK | Framework |
| `cupertino_icons` | ^1.0.8 | iOS icons |
| `webview_flutter` | ^4.10.0 | Core WebView |
| `webview_flutter_android` | ^4.3.2 | Android implementation |
| `webview_flutter_wkwebview` | ^3.16.0 | iOS/macOS implementation |
| `file_picker` | ^13.1.0 | Pick images for upload |
| `flutter_image_compress` | ^2.4.0 | Compress images before upload |
| `path_provider` | ^2.1.4 | Temp directory for compressed files |
| `url_launcher` | ^6.3.2 | Open WhatsApp links externally |
| `firebase_core` | ^4.15.0 | Firebase init |
| `firebase_messaging` | ^16.7.0 | FCM |
| `flutter_local_notifications` | ^20.0.0 | Local notif display (foreground) |

### Dev Dependencies
| Package | Purpose |
|---------|---------|
| `flutter_test` | Unit/widget tests |
| `flutter_lints` | Linting |
| `flutter_launcher_icons` | Generate app icons |
| `flutter_native_splash` | Generate splash screens |

---

## Build & Run Commands

```bash
# Get dependencies
flutter pub get

# Run on connected device/emulator
flutter run

# Build APK (Android)
flutter build apk --release

# Build App Bundle (Play Store)
flutter build appbundle --release

# Build iOS (requires Xcode)
flutter build ios --release

# Build Web
flutter build web --release

# Generate icons (after changing logo.png)
flutter pub run flutter_launcher_icons:main

# Generate splash screens
flutter pub run flutter_native_splash:create
```

---

## How Things Connect (Flow Diagram)

```
┌─────────────────────────────────────────────────────────────────┐
│                        App Launch                               │
└──────────────────────────┬──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                  main.dart: main()                              │
│  - WidgetsFlutterBinding.ensureInitialized()                    │
│  - Set orientations (portrait + landscape)                      │
│  - runApp(OregonetServiceApp())                                 │
└──────────────────────────┬──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              WebViewHomePage.initState()                        │
│  1. _createController() → WebViewController                     │
│     - Platform-specific params (Android/iOS)                    │
│     - JS unrestricted, white background                         │
│     - NavigationDelegate (load/error/finish + WhatsApp block)   │
│     - Android: setOnShowFileSelector (FilePicker + compress)    │
│     - loadRequest(kHomeUrl)                                     │
│  2. PushNotifications.init()                                    │
│     - Firebase.initializeApp()                                  │
│     - Local notifications setup (channel: tugas_baru)           │
│     - Request permission                                        │
│     - Listen: onMessage, onMessageOpenedApp, getInitialMessage  │
│     - Get FCM token → onToken → injectFcmToken() into WebView   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Common Modification Points

| Want to change... | Edit file(s) |
|-------------------|--------------|
| Target website URL | `lib/main.dart` → `kHomeUrl` |
| Brand color | `lib/main.dart` → `kBrandColor` |
| Max upload size | `lib/main.dart` → `kMaxUploadBytes` |
| Pull-to-refresh threshold | `lib/main.dart` → `_refreshTriggerDistance` |
| Image compression quality/size | `lib/main.dart` → `_compressIfImage()` attempts array |
| FCM notification channel | `lib/push_notifications.dart` → `_kChannelId`, `_kChannelName`, `_kChannelDesc` |
| Notification icon (Android) | `android/app/src/main/res/drawable/ic_stat_oregonet.xml` |
| App icon / splash screen | Replace `assets/images/logo.png` → run icon/splash generators |
| iOS permissions text | `ios/Runner/Info.plist` → usage description strings |
| WhatsApp domains | `lib/whatsapp_link.dart` → `isWhatsAppLink()` |
| Android permissions | `android/app/src/main/AndroidManifest.xml` |
| Web PWA config | `web/manifest.json` |
| FileProvider paths | `android/app/src/main/res/xml/file_paths.xml` |

---

## Firebase / Backend Integration Notes

1. **FCM Token Flow**: App gets token → `injectFcmToken()` puts it in `window.OREGONET_FCM_TOKEN` + fires `oregonet-fcm-token` event → Web page (Blade partial `push-token.blade.php`) reads it and POSTs to server.

2. **Notification Payload** (from Laravel `FcmService.php`):
   ```php
   $message = [
       'notification' => ['title' => $title, 'body' => $body],
       'data' => ['path' => $path], // e.g., "/worker/tasks/12"
       'android' => ['notification' => ['channel_id' => 'tugas_baru']],
   ];
   ```

3. **Deep Link Handling**: `onOpenPath` receives `/worker/tasks/12` → `resolveAppPath()` validates same host → `controller.loadRequest(fullUrl)`.

4. **Server Upload Limit**: 2MB. App compresses to ~1.8MB max via progressive JPEG compression.

---

## Troubleshooting Checklist

| Issue | Check |
|-------|-------|
| File upload not working (Android) | FileProvider authority in Manifest matches `${applicationId}.fileprovider`; `file_paths.xml` has `<cache-path>` |
| Notifications not showing (Android) | Channel ID `tugas_baru` matches in Dart, Manifest meta-data, AND Laravel; icon `ic_stat_oregonet` exists; `POST_NOTIFICATIONS` permission granted |
| Notifications not showing (iOS) | `GoogleService-Info.plist` added to Runner; APNs key configured in Firebase Console |
| FCM token not sent to web | `injectFcmToken()` called after `onPageFinished` + on token refresh; web page listens for `oregonet-fcm-token` event |
| WhatsApp links open in WebView | `isWhatsAppLink()` detects the URL; `NavigationDelegate.onNavigationRequest` returns `NavigationDecision.prevent` |
| Pull-to-refresh not triggering | `_dragEligible` requires scroll position at top (`scrollPos.dy <= 0`); drag distance ≥ 90px |

---

## Version & Compatibility

- **Flutter SDK**: `>=3.3.0 <4.0.0` (Dart 3.x)
- **Android minSdk**: 21 (set in `flutter_launcher_icons` config)
- **iOS min**: 12.0 (default Flutter)
- **Web**: Modern browsers (ES2017+)

---

## Generated Files (Do Not Edit Manually)

These are auto-generated — regenerate via commands above:
- `android/app/src/main/res/mipmap-*/ic_launcher.png` (icons)
- `android/app/src/main/res/drawable*/splash*.png` (splash)
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/*` (icons)
- `ios/Runner/Assets.xcassets/LaunchImage.launchimage/*` (splash)
- `web/icons/*`, `web/splash/img/*` (PWA icons/splash)
- `lib/generated_plugin_registrant.dart` (Flutter plugin registration)

---

## Testing

```bash
# Run unit/widget tests
flutter test

# Analyze code
flutter analyze
```

Test file: `test/widget_test.dart` (default Flutter counter test — replace with real tests).

---

## Git & CI Notes

- `.gitignore` excludes: `build/`, `.dart_tool/`, `*.iml`, `.idea/`, `*.log`, `google-services.json`, `GoogleService-Info.plist`
- Add `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) manually — **never commit them**
- Recommended: Add CI (GitHub Actions / Bitrise / Codemagic) for `flutter analyze`, `flutter test`, `flutter build`

---

## Quick Reference for AI Assistants

> **When asked to modify this project, check this file first.**  
> Key entry points: `lib/main.dart` (WebView, upload, refresh), `lib/push_notifications.dart` (FCM), `lib/whatsapp_link.dart` (external links).  
> Platform config: `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, `web/manifest.json`.  
> Assets: `assets/images/logo.png` → icons/splash via generators.
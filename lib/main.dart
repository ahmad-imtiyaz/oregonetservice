import 'dart:io';

import 'package:flutter/material.dart';
import 'whatsapp_link.dart';
import 'push_notifications.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// URL utama yang ditampilkan di WebView.
const String kHomeUrl = 'https://oregonetservice.my.id/';

/// Warna brand, diambil dari logo Oregonet.
const Color kBrandColor = Color(0xFF8B0021);

/// Batas ukuran upload dari form web (server membatasi 2MB).
const int kMaxUploadBytes = 1800 * 1024; // sisakan margin di bawah 2MB

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Orientasi bebas (portrait & landscape).
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const OregonetServiceApp());
}

class OregonetServiceApp extends StatelessWidget {
  const OregonetServiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oregonet Service',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kBrandColor),
        useMaterial3: true,
      ),
      home: const WebViewHomePage(),
    );
  }
}

class WebViewHomePage extends StatefulWidget {
  const WebViewHomePage({super.key});

  @override
  State<WebViewHomePage> createState() => _WebViewHomePageState();
}

class _WebViewHomePageState extends State<WebViewHomePage> {
  late final WebViewController _controller;
  late final PushNotifications _push;
  String? _fcmToken;

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isPickingFile = false;
  bool _hasError = false;

  static const MethodChannel _fileProviderChannel =
      MethodChannel('com.oregonetservice/fileprovider');
  // State untuk gesture pull-to-refresh manual (dipantau lewat Listener,
  // bukan GestureDetector, supaya scroll WebView tidak ikut ke-block).
  double _dragDistance = 0;
  bool _dragEligible = false;
  double? _dragStartY;
  static const double _refreshTriggerDistance = 90;

  @override
  void initState() {
    super.initState();
    _controller = _createController();

    _push = PushNotifications(
      onToken: (token) {
        _fcmToken = token;
        injectFcmToken(_controller, token);
      },
      onOpenPath: (path) {
        final uri = resolveAppPath(path, Uri.parse(kHomeUrl));
        if (uri != null) _controller.loadRequest(uri);
      },
    );
    _push.init();
  }

  /// Kompres gambar (JPG/PNG) supaya di bawah batas server.
  /// File non-gambar dikembalikan apa adanya.
  Future<String> _compressIfImage(String path) async {
    final lower = path.toLowerCase();
    final isImage = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');
    if (!isImage) return path;

    // Kalau sudah cukup kecil, tidak perlu dikompres.
    if (await File(path).length() <= kMaxUploadBytes) return path;

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // Coba beberapa level kualitas sampai ukurannya masuk batas.
    const attempts = [
      (quality: 80, size: 1600),
      (quality: 65, size: 1280),
      (quality: 50, size: 1024),
    ];

    String best = path;
    for (final a in attempts) {
      final target = '${dir.path}/proof_${stamp}_${a.quality}.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        path,
        target,
        quality: a.quality,
        minWidth: a.size,
        minHeight: a.size,
        format: CompressFormat.jpeg,
      );
      if (result == null) continue;
      best = result.path;
      if (await File(best).length() <= kMaxUploadBytes) break;
    }
    debugPrint(
        'Compressed: $path -> $best (${await File(best).length()} bytes)');
    return best;
  }

  /// Konversi path file lokal jadi content:// URI lewat FileProvider,
  /// supaya WebView (proses Chromium-nya) bisa baca file dari cache
  /// privat app. Fallback ke file:// kalau channel-nya gagal.
  Future<String> _toContentUri(String path) async {
    try {
      final uri = await _fileProviderChannel.invokeMethod<String>(
        'getUriForFile',
        {'path': path},
      );
      if (uri != null) return uri;
    } catch (e) {
      debugPrint('FileProvider channel error: $e');
    }
    return Uri.file(path).toString();
  }

  WebViewController _createController() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
            }
          },
          onPageFinished: (_) {
            final token = _fcmToken;
            if (token != null) injectFcmToken(_controller, token);
            if (mounted) {
              setState(() {
                _isLoading = false;
                _isRefreshing = false;
              });
            }
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _isRefreshing = false;
                if (error.isForMainFrame ?? true) {
                  _hasError = true;
                }
              });
            }
          },
          // Semua navigasi tetap ditangani di dalam WebView ini.
          // Tidak pernah dilempar ke Chrome/Edge/browser lain.
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && isWhatsAppLink(uri)) {
              openExternally(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(kHomeUrl));

    // Dukungan upload file/foto dari form web (Android).
    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
      AndroidWebViewController.enableDebugging(true);
      androidController.setOnShowFileSelector((params) async {
        if (_isPickingFile) return <String>[];
        _isPickingFile = true;
        try {
          final List<PlatformFile> files;
          if (params.mode == FileSelectorMode.openMultiple) {
            files = await FilePicker.pickFiles(type: FileType.image);
          } else {
            final single = await FilePicker.pickFile(type: FileType.image);
            files = single == null ? <PlatformFile>[] : <PlatformFile>[single];
          }
          debugPrint('File picker result: '
              '${files.map((f) => '${f.name} -> ${f.path}').toList()}');

          final uris = <String>[];
          for (final f in files) {
            if (f.path == null) continue;
            final finalPath = await _compressIfImage(f.path!);
            uris.add(await _toContentUri(finalPath));
          }
          return uris;
        } catch (e, st) {
          debugPrint('File selector error: $e\n$st');
          return <String>[];
        } finally {
          _isPickingFile = false;
        }
      });
    }
    // Catatan iOS: WKWebView (dipakai lewat webview_flutter_wkwebview)
    // sudah menampilkan file chooser native untuk <input type="file">
    // selama NSCameraUsageDescription & NSPhotoLibraryUsageDescription
    // sudah diisi di Info.plist — tidak perlu callback tambahan.

    return controller;
  }

  Future<void> _reload() async {
    setState(() => _isRefreshing = true);
    await _controller.reload();
  }

  /// true jika app boleh benar-benar keluar (popped),
  /// false jika sudah ditangani (goBack di WebView / dialog dibatalkan).
  Future<bool> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    if (!mounted) return false;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar Aplikasi'),
        content:
            const Text('Apakah kamu yakin ingin keluar dari aplikasi ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: kBrandColor),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  Future<void> _onPointerDown(PointerDownEvent event) async {
    if (_isRefreshing) return;
    _dragStartY = event.position.dy;
    _dragEligible = false;
    final scrollPos = await _controller.getScrollPosition();
    // Pastikan pointer masih di posisi awal saat hasil async ini kembali
    // (belum di-release / belum ganti drag baru).
    if (_dragStartY == event.position.dy) {
      _dragEligible = scrollPos.dy <= 0;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_dragEligible || _isRefreshing || _dragStartY == null) return;
    final delta = event.position.dy - _dragStartY!;
    if (delta > 0) {
      setState(() {
        _dragDistance = delta.clamp(0, _refreshTriggerDistance * 1.5);
      });
    } else if (_dragDistance != 0) {
      setState(() => _dragDistance = 0);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _finishDrag();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _finishDrag();
  }

  void _finishDrag() {
    if (!_dragEligible) {
      _dragStartY = null;
      return;
    }
    final shouldRefresh = _dragDistance >= _refreshTriggerDistance;
    setState(() {
      _dragDistance = 0;
      _dragEligible = false;
    });
    _dragStartY = null;
    if (shouldRefresh) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _handleBack();
        if (shouldPop) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        // Sengaja tanpa AppBar — cuma halaman web murni.
        body: SafeArea(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_hasError)
                  Container(
                    color: Colors.white,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded,
                            size: 56, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          'Gagal memuat halaman.\nPeriksa koneksi internet kamu.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.black87),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            setState(() => _hasError = false);
                            _controller.reload();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kBrandColor,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                if (_dragDistance > 0 || _isRefreshing)
                  Positioned(
                    top: _isRefreshing ? 16 : (_dragDistance / 1.5) - 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: SizedBox(
                        height: 30,
                        width: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          value: _isRefreshing
                              ? null
                              : (_dragDistance / _refreshTriggerDistance)
                                  .clamp(0, 1),
                          color: kBrandColor,
                        ),
                      ),
                    ),
                  ),
                if (_isLoading && !_isRefreshing)
                  const Center(
                    child: CircularProgressIndicator(color: kBrandColor),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

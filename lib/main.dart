import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:file_picker/file_picker.dart';

/// URL utama yang ditampilkan di WebView.
const String kHomeUrl = 'https://oregonetservice.my.id/';

/// Warna brand, diambil dari logo Oregonet.
const Color kBrandColor = Color(0xFF8B0021);

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

  bool _isLoading = true;
  bool _isRefreshing = false;

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
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _isRefreshing = false;
              });
            }
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _isRefreshing = false;
              });
            }
          },
          // Semua navigasi tetap ditangani di dalam WebView ini.
          // Tidak pernah dilempar ke Chrome/Edge/browser lain.
          onNavigationRequest: (request) => NavigationDecision.navigate,
        ),
      )
      ..loadRequest(Uri.parse(kHomeUrl));

    // Dukungan upload file/foto dari form web (Android).
    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setOnShowFileSelector((params) async {
        try {
          final List<PlatformFile> files;
          if (params.mode == FileSelectorMode.openMultiple) {
            files = await FilePicker.pickFiles(type: FileType.any);
          } else {
            final single = await FilePicker.pickFile(type: FileType.any);
            files = single == null ? <PlatformFile>[] : <PlatformFile>[single];
          }
          return files
              .where((f) => f.path != null)
              .map((f) => Uri.file(f.path!).toString())
              .toList();
        } catch (_) {
          return <String>[];
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

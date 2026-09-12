import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nobarin/features/lobby/data/google_drive_auth_service.dart';
import 'package:nobarin/features/lobby/data/google_drive_service.dart';
import 'package:nobarin/features/lobby/data/models/google_drive_video_model.dart';
import 'package:nobarin/features/lobby/presentation/screens/google_drive_picker_screen.dart';

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpClientRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientRequest implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientResponse implements HttpClientResponse {
  static final _transparentImage = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
    0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
    0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44,
    0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
    0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
    0x60, 0x82,
  ];

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _transparentImage.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream.value(_transparentImage).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleDriveService.resetMockVideos();
  });

  testWidgets('GoogleDrivePickerScreen renders tabs and connect card initially',
      (tester) async {
    // Ensure signed out
    await GoogleDriveAuthService.instance.signOut();

    await tester.pumpWidget(
      const MaterialApp(
        home: GoogleDrivePickerScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Tabs
    expect(find.text('Google Drive Video'), findsOneWidget);
    expect(find.text('Drive Saya'), findsOneWidget);
    expect(find.text('Koleksi Publik'), findsOneWidget);

    // Verify Connect Account Card
    expect(find.text('Hubungkan Akun Google Drive'), findsOneWidget);
    expect(find.text('Login dengan Google'), findsOneWidget);
    expect(find.text('Coba Mode Demo / Simulasi'), findsOneWidget);
  });

  testWidgets('signing in with demo mode loads personal videos and account header',
      (tester) async {
    await GoogleDriveAuthService.instance.signOut();

    await tester.pumpWidget(
      const MaterialApp(
        home: GoogleDrivePickerScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // Tap Demo sign in
    await tester.tap(find.text('Coba Mode Demo / Simulasi'));
    await tester.pump();
    await tester.pumpAndSettle();

    // Verify account header appears
    expect(find.text('Pengguna Google Drive'), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);

    // Verify user video list rendered
    expect(find.text('Liburan_Keluarga_Bali_2026.mp4'), findsOneWidget);
    expect(find.text('Privat (Perlu Izin)'), findsWidgets);
  });

  testWidgets('tapping private video shows permission confirmation sheet',
      (tester) async {
    // Start already signed in
    await GoogleDriveAuthService.instance.signIn(forceMock: true);

    GoogleDriveVideo? selectedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              selectedResult = await Navigator.of(context).push<GoogleDriveVideo>(
                MaterialPageRoute(
                  builder: (_) => const GoogleDrivePickerScreen(),
                ),
              );
            },
            child: const Text('Open Picker'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    // Find and tap the private video
    final privateVideoFinder = find.text('Liburan_Keluarga_Bali_2026.mp4');
    expect(privateVideoFinder, findsOneWidget);

    await tester.tap(privateVideoFinder);
    await tester.pumpAndSettle();

    // Verify permission confirmation sheet is displayed
    expect(find.text('Aktifkan Izin Room Nonton'), findsOneWidget);
    expect(find.text('Izinkan & Putar'), findsOneWidget);

    // Tap "Izinkan & Putar"
    await tester.tap(find.text('Izinkan & Putar'));
    await tester.pump();
    await tester.pumpAndSettle();

    // Verify screen popped and returned video with isPublic == true
    expect(selectedResult, isNotNull);
    expect(selectedResult!.id, 'mock_v1_liburan_bali_2026');
    expect(selectedResult!.isPublic, isTrue);
  });
}

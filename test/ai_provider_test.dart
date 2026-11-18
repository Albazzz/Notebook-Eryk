import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteeryk/app_state.dart';
import 'package:noteeryk/models.dart';
import 'package:noteeryk/screens/settings_screen.dart';
import 'package:noteeryk/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AI settings allow selecting Vercel and entering its key', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final state = AppState()..autoSave = false;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsScreen(state: state)),
      ),
    );
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.text('OpenRouter'), findsOneWidget);
    expect(find.text('Gemini'), findsOneWidget);
    await tester.tap(find.text('Vercel AI Gateway'));
    await tester.pumpAndSettle();
    expect(state.aiProvider, AiProvider.vercel);
    expect(find.text('AI qua Vercel AI Gateway'), findsOneWidget);
    expect(find.text('VERCEL AI GATEWAY API KEY'), findsOneWidget);
    expect(find.textContaining(AiProvider.vercel.keyUrl), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('OpenRouter requests identify the app as AIcall', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final urls = <Uri>[];
    final requests = <HttpRequest>[];
    server.listen((request) async {
      requests.add(request);
      request.response.write('{}');
      await request.response.close();
    });

    await HttpOverrides.runWithHttpOverrides(() async {
      final service = OpenRouterService();
      addTearDown(service.dispose);
      await service.testConnection(' "test-key" ');
    }, _RedirectingHttpOverrides(server.port, urls));

    expect(urls.single.toString(), 'https://openrouter.ai/api/v1/key');
    expect(requests.single.headers.value('X-Title'), 'AIcall');
    expect(requests.single.headers.value('Authorization'), 'Bearer test-key');
  });

  test('Vercel checks credentials and loads its own model catalog', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final urls = <Uri>[];
    final requests = <HttpRequest>[];
    server.listen((request) async {
      requests.add(request);
      if (request.headers.value('Authorization') != 'Bearer vercel-test-key') {
        request.response.statusCode = 401;
        request.response.write('{}');
      } else if (request.uri.path == '/v1/credits') {
        request.response.write('{"balance":"0","total_used":"0"}');
      } else if (request.uri.path == '/v1/models') {
        request.response.write(
          jsonEncode({
            'data': [
              {
                'id': 'google/gemini-3.8-flash',
                'name': 'Gemini 3.8 Flash',
                'type': 'language',
                'context_window': 1000000,
                'modalities': {
                  'input': ['text', 'image'],
                  'output': ['text'],
                },
                'pricing': {'input': '0.000001', 'output': '0.000002'},
              },
            ],
          }),
        );
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });

    await HttpOverrides.runWithHttpOverrides(() async {
      final service = OpenRouterService()..provider = AiProvider.vercel;
      addTearDown(service.dispose);
      await expectLater(
        service.testConnection('invalid-test-key'),
        throwsA(isA<HttpException>()),
      );
      await service.testConnection('vercel-test-key');
      final models = await service.listModels('vercel-test-key');
      expect(models.single.id, 'google/gemini-3.8-flash');
      expect(models.single.contextLength, 1000000);
      expect(models.single.vision, isTrue);
      expect(models.single.free, isFalse);
    }, _RedirectingHttpOverrides(server.port, urls));

    expect(urls.map((url) => url.toString()), [
      'https://ai-gateway.vercel.sh/v1/credits',
      'https://ai-gateway.vercel.sh/v1/credits',
      'https://ai-gateway.vercel.sh/v1/models',
    ]);
    for (final request in requests) {
      expect(request.headers.value('X-Title'), isNull);
      expect(request.headers.value('HTTP-Referer'), isNull);
    }
  });

  test('Vercel payload supports reasoning without OpenRouter extensions', () {
    final service = OpenRouterService()
      ..provider = AiProvider.vercel
      ..reasoningEffort = AiReasoningEffort.medium;
    addTearDown(service.dispose);
    final payload = service.chatPayloadForTesting(
      modelId: 'google/gemini-3.8-flash',
    );
    expect(payload.containsKey('provider'), isFalse);
    expect(payload.containsKey('plugins'), isFalse);
    expect(payload['reasoning'], {'effort': 'medium', 'exclude': true});
    expect((payload['response_format'] as Map)['type'], 'json_schema');
    final plain = service.chatPayloadForTesting(
      modelId: 'google/gemini-3.8-flash',
      reasoning: false,
    );
    expect(plain.containsKey('reasoning'), isFalse);
    final fallback = service.chatPayloadForTesting(
      modelId: 'google/gemini-3.8-flash',
      jsonObjectOnly: true,
    );
    expect(fallback['response_format'], {'type': 'json_object'});
  });

  test(
    'Vercel catalog filters non-text models and reads pricing correctly',
    () {
      final models = OpenRouterService.parseVercelModels([
        {'id': 'test/embedding', 'type': 'embedding'},
        {'id': 'test/speech', 'type': 'speech'},
        {
          'id': 'test/image',
          'type': 'language',
          'modalities': {
            'output': ['image'],
          },
        },
        {
          'id': 'test/free',
          'type': 'language',
          'pricing': {'input': '0.0', 'output': 0},
        },
        {
          'id': 'test/paid-output',
          'pricing': {'input': '0', 'output': '0.1'},
        },
        {'id': 'test/minimal'},
        {'id': ''},
      ]);
      expect(models.map((model) => model.id), [
        'test/free',
        'test/paid-output',
        'test/minimal',
      ]);
      expect(models.map((model) => model.free), [true, false, false]);
    },
  );
}

// Exercise the real HTTP code against a local server while recording the
// destination chosen by the service. No credentials leave the test process.
class _RedirectingHttpOverrides extends HttpOverrides {
  _RedirectingHttpOverrides(this.port, this.urls);
  final int port;
  final List<Uri> urls;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RedirectingHttpClient(super.createHttpClient(context), port, urls);
}

class _RedirectingHttpClient implements HttpClient {
  _RedirectingHttpClient(this.client, this.port, this.urls);
  final HttpClient client;
  final int port;
  final List<Uri> urls;

  @override
  set connectionTimeout(Duration? timeout) =>
      client.connectionTimeout = timeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    urls.add(url);
    return client.openUrl(
      method,
      url.replace(scheme: 'http', host: '127.0.0.1', port: port),
    );
  }

  @override
  void close({bool force = false}) => client.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Đo tốc độ và độ chính xác của các model OpenRouter với đúng prompt/schema
// của app. Không chạy cùng `flutter test` mặc định (nằm ngoài thư mục test/).
//
// Điền key vào file .env ở thư mục gốc (đã nằm trong .gitignore) rồi chạy:
//   flutter test tool/ai_benchmark_test.dart
// Các khóa trong .env (biến môi trường cùng tên sẽ được ưu tiên):
//   OPENROUTER_API_KEY=sk-or-...
//   AI_BENCH_MODELS=anthropic/claude-haiku-5.5,openai/gpt-6-luna
//   AI_BENCH_EFFORT=low | medium | high   (mặc định medium)
// Báo cáo chi tiết: build/ai_benchmark/report.md
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noteeryk/models.dart';
import 'package:noteeryk/services.dart';

/// Văn bản giống Apple Vision trả về: mất gạch chân, không có furigana.
const _samples = <_Sample>[
  _Sample(
    name: 'Câu đơn · 用法',
    text: '''35 ばったり
1 帰宅途中で、大学時代の友人にばったり出会った。
2 ホテルのベランダから富士山がばったり見える。
3 まず基礎をばったり身につけることが大切だ。
4 夕べはばったり寝たので疲れがとれた。''',
    answers: {'35': '1'},
    focusTerms: ['ばったり'],
  ),
  _Sample(
    name: 'Từ vựng · 言い換え',
    text: '''27 試合に負けて、くやしい思いをした。
1 苦手だった 2 残念だった 3 平気だった 4 不満だった
28 どうぞ、おかけになってください。
1 すわって 2 たべて 3 はいって 4 おりて''',
    answers: {'27': '2', '28': '1'},
    focusTerms: ['くやしい', 'おかけになって'],
  ),
  _Sample(
    name: 'Đoạn văn · 内容理解',
    text: '''平成22年4月15日
木村佳子様
三陽産業株式会社
人事部
拝啓 時下ますますご清祥のこととお喜び申し上げます。
このたびは、当社の社員募集にご応募いただき、ありがとうございました。
さて、厳正な審査の結果、採用内定と決まりましたので、お知らせ申し上げます。
なお、入社までに必要なタイムスケジュールに従って、同封いたしました書類のご返送をお願いいたします。
まずは採用内定のご通知まで。
敬具
24 この手紙の内容について、正しいのはどれか。
1 木村さんは、これから応募の資料を「三陽産業株式会社」に送る。
2 木村さんは、これから採用決定の通知を「三陽産業株式会社」に送る。
3 木村さんは、これから入社に必要な書類を「三陽産業株式会社」に送る。
4 木村さんは、これからタイムスケジュールの資料を「三陽産業株式会社」に送る。''',
    answers: {'24': '3'},
    focusTerms: ['同封', '返送'],
    translate: true,
  ),
];

const _defaultModels = [
  'anthropic/claude-haiku-5.5',
  'google/gemini-3.8-flash',
  'openai/gpt-6-luna',
  'openai/gpt-5.6-luna',
  'anthropic/claude-sonnet-5.5',
  'openai/gpt-5.6-terra',
];

const _language = 'Tiếng Việt';
const _jlpt = 'N3';

/// Đọc .env đơn giản (KEY=value, bỏ dòng # và dấu nháy bao quanh).
Map<String, String> _loadEnv() {
  final values = <String, String>{};
  final file = File('.env');
  if (file.existsSync()) {
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      final separator = trimmed.indexOf('=');
      if (trimmed.startsWith('#') || separator <= 0) continue;
      var value = trimmed.substring(separator + 1).trim();
      if (value.length >= 2 &&
          (value.startsWith('"') && value.endsWith('"') ||
              value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      values[trimmed.substring(0, separator).trim()] = value;
    }
  }
  for (final entry in Platform.environment.entries) {
    if (entry.value.trim().isNotEmpty) values[entry.key] = entry.value;
  }
  return values;
}

void main() {
  final env = _loadEnv();
  final apiKey = env['OPENROUTER_API_KEY'] ?? '';
  final models = (env['AI_BENCH_MODELS'] ?? '')
      .split(',')
      .map((model) => model.trim())
      .where((model) => model.isNotEmpty)
      .toList();
  final effort = AiReasoningEffort.values.firstWhere(
    (value) => value.name == env['AI_BENCH_EFFORT'],
    orElse: () => AiReasoningEffort.medium,
  );

  test(
    'AI model benchmark',
    () async {
      final results = await Future.wait([
        for (final model in models.isEmpty ? _defaultModels : models)
          _benchmarkModel(apiKey, model, effort),
      ]);
      final report = _report(results, effort);
      final file = File('build/ai_benchmark/report.md');
      await file.parent.create(recursive: true);
      await file.writeAsString(report.full);
      // ignore: avoid_print
      print('\n${report.summary}\nBáo cáo chi tiết: ${file.absolute.path}');
    },
    skip: apiKey.isEmpty
        ? 'Điền OPENROUTER_API_KEY trong file .env để chạy benchmark'
        : false,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

class _Sample {
  const _Sample({
    required this.name,
    required this.text,
    required this.answers,
    required this.focusTerms,
    this.translate = false,
  });
  final String name;
  final String text;

  /// Số câu → nhãn đáp án đúng.
  final Map<String, String> answers;
  final List<String> focusTerms;
  final bool translate;
}

class _Run {
  _Run(this.task, this.sample, this.elapsed, this.output, {this.error});
  final String task;
  final String sample;
  final Duration elapsed;
  final String output;
  final Object? error;
  int correct = 0;
  int total = 0;
  bool japaneseExplanation = false;
}

class _ModelResult {
  _ModelResult(this.model);
  final String model;
  final List<_Run> runs = [];
}

String _digits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

Future<_Run> _timed(
  String task,
  String sample,
  Future<String> Function() body,
) async {
  final watch = Stopwatch()..start();
  try {
    final output = await body();
    return _Run(task, sample, watch.elapsed, output);
  } catch (error) {
    return _Run(task, sample, watch.elapsed, '', error: error);
  }
}

Future<_ModelResult> _benchmarkModel(
  String apiKey,
  String model,
  AiReasoningEffort effort,
) async {
  final service = OpenRouterService()..reasoningEffort = effort;
  final result = _ModelResult(model);
  try {
    for (final sample in _samples) {
      QuickCheckResult? check;
      final quick = await _timed('Kiểm tra nhanh', sample.name, () async {
        check = await service.completeQuickCheck(
          apiKey: apiKey,
          modelId: model,
          text: sample.text,
          jlpt: _jlpt,
          language: _language,
        );
        return [
          for (final question in check!.questions)
            [
              'Câu ${question.label} → ${question.correctText}',
              question.explanation,
              for (final choice in question.choices)
                '  ${choice.correct ? '✓' : '✗'} ${choice.label}. ${choice.text}: ${choice.reason}',
            ].join('\n'),
          if (check!.warning.isNotEmpty) 'Cảnh báo: ${check!.warning}',
        ].join('\n\n');
      });
      final checked = check;
      quick.total = sample.answers.length;
      if (checked != null) {
        for (final question in checked.questions) {
          final expected = sample.answers[_digits(question.label)];
          final index = question.correctIndex;
          if (expected == null || index < 0) continue;
          if (_digits(question.choices[index].label) == expected) {
            quick.correct++;
          }
        }
        quick.japaneseExplanation = checked.questions.any(
          (question) => looksJapaneseOnly(question.explanation),
        );
      }
      result.runs.add(quick);

      result.runs.add(
        await _timed(
          'Giải thích',
          sample.name,
          () => service.complete(
            apiKey: apiKey,
            modelId: model,
            task: AiTask.explain,
            text: sample.text,
            jlpt: _jlpt,
            language: _language,
          ),
        ),
      );

      if (sample.translate) {
        result.runs.add(
          await _timed(
            'Dịch',
            sample.name,
            () => service.complete(
              apiKey: apiKey,
              modelId: model,
              task: AiTask.translate,
              text: sample.text,
              jlpt: _jlpt,
              language: _language,
            ),
          ),
        );
      }

      result.runs.add(
        await _timed('Điểm yếu (đã tô)', sample.name, () async {
          final drafts = await service.completeWeakPointDrafts(
            apiKey: apiKey,
            modelId: model,
            text: sample.text,
            jlpt: _jlpt,
            language: _language,
            focusTerms: sample.focusTerms,
          );
          return drafts.items
              .map(
                (item) => [
                  '[${item.kind.name}] ${item.title} (${item.reading}) — ${item.content}',
                  if (item.mistake.isNotEmpty) '  Dễ nhầm: ${item.mistake}',
                ].join('\n'),
              )
              .join('\n');
        }),
      );
    }
  } finally {
    service.dispose();
  }
  return result;
}

({String summary, String full}) _report(
  List<_ModelResult> results,
  AiReasoningEffort effort,
) {
  String seconds(Duration value) =>
      (value.inMilliseconds / 1000).toStringAsFixed(1);
  Duration average(Iterable<_Run> runs) {
    final ok = runs.where((run) => run.error == null).toList();
    if (ok.isEmpty) return Duration.zero;
    return ok.fold(Duration.zero, (sum, run) => sum + run.elapsed) ~/ ok.length;
  }

  final summary = StringBuffer()
    ..writeln('Mức suy luận: ${effort.name} · JLPT $_jlpt · $_language')
    ..writeln(
      '| Model | Đúng | KT nhanh (s) | Giải thích (s) | Dịch (s) | Điểm yếu (s) | Lỗi | Giải thích tiếng Nhật |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|');
  for (final result in results) {
    Iterable<_Run> task(String name) =>
        result.runs.where((run) => run.task == name);
    final checks = task('Kiểm tra nhanh');
    final correct = checks.fold(0, (sum, run) => sum + run.correct);
    final total = checks.fold(0, (sum, run) => sum + run.total);
    summary.writeln(
      '| ${result.model} | $correct/$total '
      '| ${seconds(average(checks))} '
      '| ${seconds(average(task('Giải thích')))} '
      '| ${seconds(average(task('Dịch')))} '
      '| ${seconds(average(task('Điểm yếu (đã tô)')))} '
      '| ${result.runs.where((run) => run.error != null).length} '
      '| ${checks.where((run) => run.japaneseExplanation).length} |',
    );
  }

  final full = StringBuffer('# Benchmark AI\n\n$summary\n');
  for (final result in results) {
    full.writeln('\n## ${result.model}\n');
    for (final run in result.runs) {
      full
        ..writeln(
          '### ${run.task} · ${run.sample} · ${seconds(run.elapsed)} s'
          '${run.total > 0 ? ' · đúng ${run.correct}/${run.total}' : ''}\n',
        )
        ..writeln('```')
        ..writeln(run.error != null ? 'LỖI: ${run.error}' : run.output)
        ..writeln('```\n');
    }
  }
  return (summary: summary.toString(), full: full.toString());
}

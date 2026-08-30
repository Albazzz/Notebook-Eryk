import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart source does not contain common UTF-8 mojibake', () {
    const brokenSequences = <String>[
      'Ã',
      'Ä',
      'Æ',
      'áº',
      'á»',
      'â€',
      'Â·',
      'ï¿½',
      '\uFFFD',
    ];
    final failures = <String>[];

    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        if (brokenSequences.any(lines[index].contains)) {
          failures.add('${file.path}:${index + 1}: ${lines[index].trim()}');
        }
      }
    }

    expect(
      failures,
      isEmpty,
      reason:
          'Phát hiện chuỗi tiếng Việt bị lỗi mã hóa:\n${failures.join('\n')}',
    );
  });
}

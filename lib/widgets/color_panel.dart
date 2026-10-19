import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Màu mẫu cố định của bảng màu (hàng swatch đầu tiên).
const colorPanelPresets = <Color>[
  Color(0xff1f2633),
  Color(0xff000000),
  Color(0xff5f6368),
  Color(0xffffffff),
  Color(0xffc8453b),
  Color(0xffe8710a),
  Color(0xfff4c542),
  Color(0xff2e8b57),
  Color(0xff66cc99),
  Color(0xff0f8b8d),
  Color(0xff3979d6),
  Color(0xff244a98),
  Color(0xff7a5bc7),
  Color(0xffd81b60),
  Color(0xff8a5a44),
  Color(0xffef83a7),
];

/// Bảng màu kiểu ứng dụng vẽ: xem trước màu mới/cũ, thanh R/G/B, mã hex,
/// màu mẫu + màu gần đây, vòng sắc độ với ô bão hòa/độ sáng và độ mờ.
/// [color] là màu đặc (alpha bỏ qua), [opacity] là độ đậm 0..1.
class ColorPanel extends StatefulWidget {
  const ColorPanel({
    super.key,
    required this.color,
    required this.opacity,
    required this.onChanged,
    this.recentColors = const [],
    this.minOpacity = .1,
    this.maxOpacity = 1,
    this.opacityLabel = 'Độ đậm',
  });

  final Color color;
  final double opacity;
  final void Function(Color color, double opacity) onChanged;
  final List<Color> recentColors;
  final double minOpacity;
  final double maxOpacity;
  final String opacityLabel;

  @override
  State<ColorPanel> createState() => _ColorPanelState();
}

class _ColorPanelState extends State<ColorPanel> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color.withValues(alpha: 1));
  late double _opacity = widget.opacity;
  late final Color _original = widget.color.withValues(alpha: 1);
  late final TextEditingController _hex = TextEditingController(
    text: _hexOf(_hsv.toColor()),
  );
  final FocusNode _hexFocus = FocusNode();

  @override
  void dispose() {
    _hex.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  static int _channel(double value) => (value * 255).round().clamp(0, 255);

  static String _hexOf(Color color) => [color.r, color.g, color.b]
      .map((value) => _channel(value).toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  Color get _color => _hsv.toColor();

  void _emit() {
    if (!_hexFocus.hasFocus) _hex.text = _hexOf(_color);
    widget.onChanged(_color, _opacity);
  }

  void _setHsv(HSVColor value) {
    setState(() => _hsv = value);
    _emit();
  }

  void _setColor(Color color) {
    final next = HSVColor.fromColor(color.withValues(alpha: 1));
    // Grey has no hue; keep the current one so the ring marker stays put.
    _setHsv(next.saturation == 0 ? next.withHue(_hsv.hue) : next);
  }

  void _setChannel(int index, double value) {
    final color = _color;
    final channels = [color.r, color.g, color.b]..[index] = value;
    _setColor(
      Color.from(
        alpha: 1,
        red: channels[0],
        green: channels[1],
        blue: channels[2],
      ),
    );
  }

  void _onHexSubmitted(String raw) {
    final value = raw.replaceAll('#', '').trim();
    final parsed = int.tryParse(value, radix: 16);
    if (value.length == 6 && parsed != null) {
      _setColor(Color(0xff000000 | parsed));
    } else {
      _hex.text = _hexOf(_color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color;
    final channelColors = [
      (const Color(0xffe53935), 'R'),
      (const Color(0xff43a047), 'G'),
      (const Color(0xff1e88e5), 'B'),
    ];
    final channels = [color.r, color.g, color.b];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PreviewSwatch(
              current: color.withValues(alpha: _opacity),
              previous: _original,
              onRestore: () => _setColor(_original),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                children: [
                  for (var index = 0; index < 3; index++)
                    _ChannelRow(
                      label: channelColors[index].$2,
                      value: channels[index],
                      start: Color.from(
                        alpha: 1,
                        red: index == 0 ? 0 : color.r,
                        green: index == 1 ? 0 : color.g,
                        blue: index == 2 ? 0 : color.b,
                      ),
                      end: Color.from(
                        alpha: 1,
                        red: index == 0 ? 1 : color.r,
                        green: index == 1 ? 1 : color.g,
                        blue: index == 2 ? 1 : color.b,
                      ),
                      onChanged: (value) => _setChannel(index, value),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('#', style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(width: 6),
            SizedBox(
              width: 120,
              child: TextField(
                key: const ValueKey('color-panel-hex'),
                controller: _hex,
                focusNode: _hexFocus,
                maxLength: 7,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
                ],
                decoration: const InputDecoration(
                  counterText: '',
                  isDense: true,
                ),
                onSubmitted: _onHexSubmitted,
                onTapOutside: (_) {
                  if (_hexFocus.hasFocus) {
                    _onHexSubmitted(_hex.text);
                    _hexFocus.unfocus();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SwatchRow(
          colors: colorPanelPresets,
          selected: color,
          onTap: _setColor,
        ),
        if (widget.recentColors.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Màu đã dùng gần đây',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          _SwatchRow(
            colors: widget.recentColors,
            selected: color,
            onTap: _setColor,
          ),
        ],
        const SizedBox(height: 14),
        Center(
          child: _HueRingPicker(hsv: _hsv, onChanged: _setHsv),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(width: 70, child: Text(widget.opacityLabel)),
            Expanded(
              child: _GradientSlider(
                key: const ValueKey('color-panel-opacity'),
                value:
                    ((_opacity - widget.minOpacity) /
                            (widget.maxOpacity - widget.minOpacity))
                        .clamp(0.0, 1.0),
                colors: [
                  color.withValues(alpha: widget.minOpacity),
                  color.withValues(alpha: widget.maxOpacity),
                ],
                checkerboard: true,
                onChanged: (value) {
                  setState(
                    () => _opacity =
                        widget.minOpacity +
                        value * (widget.maxOpacity - widget.minOpacity),
                  );
                  _emit();
                },
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                '${(_opacity * 100).round()}%',
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreviewSwatch extends StatelessWidget {
  const _PreviewSwatch({
    required this.current,
    required this.previous,
    required this.onRestore,
  });

  final Color current;
  final Color previous;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).colorScheme.outlineVariant;
    return SizedBox(
      width: 64,
      height: 92,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Tooltip(
              message: 'Màu mới',
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: CustomPaint(
                    painter: _CheckerPainter(),
                    child: ColoredBox(color: current),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 26,
            top: 58,
            child: Tooltip(
              message: 'Màu trước đó · chạm để dùng lại',
              child: GestureDetector(
                onTap: onRestore,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: previous,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: border),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.label,
    required this.value,
    required this.start,
    required this.end,
    required this.onChanged,
  });

  final String label;
  final double value;
  final Color start;
  final Color end;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: _GradientSlider(
            key: ValueKey('color-panel-$label'),
            value: value,
            colors: [start, end],
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(value * 255).round()}',
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Thanh trượt có nền dải màu; kéo hoặc chạm để chọn giá trị 0..1.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    super.key,
    required this.value,
    required this.colors,
    required this.onChanged,
    this.checkerboard = false,
  });

  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;
  final bool checkerboard;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const thumb = 18.0;
      final width = constraints.maxWidth;
      void update(Offset local) =>
          onChanged(((local.dx - thumb / 2) / (width - thumb)).clamp(0.0, 1.0));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => update(details.localPosition),
        onHorizontalDragStart: (details) => update(details.localPosition),
        onHorizontalDragUpdate: (details) => update(details.localPosition),
        child: SizedBox(
          height: 28,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: thumb / 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CustomPaint(
                    painter: checkerboard ? _CheckerPainter() : null,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: colors),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: value * (width - thumb),
                child: Container(
                  width: thumb,
                  height: thumb,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.black54, width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 3),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow({
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onTap;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final color in colors)
          GestureDetector(
            onTap: () => onTap(color),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: color.toARGB32() == selected.toARGB32()
                      ? Theme.of(context).colorScheme.primary
                      : outline.withValues(alpha: .4),
                  width: color.toARGB32() == selected.toARGB32() ? 3 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Vòng sắc độ bao quanh ô vuông bão hòa (ngang) × độ sáng (dọc).
class _HueRingPicker extends StatefulWidget {
  const _HueRingPicker({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  static const size = 240.0;
  static const ringWidth = 22.0;

  @override
  State<_HueRingPicker> createState() => _HueRingPickerState();
}

enum _RingTarget { none, ring, square }

class _HueRingPickerState extends State<_HueRingPicker> {
  _RingTarget _target = _RingTarget.none;

  static const _center = Offset(
    _HueRingPicker.size / 2,
    _HueRingPicker.size / 2,
  );
  static const _outer = _HueRingPicker.size / 2;
  static const _inner = _outer - _HueRingPicker.ringWidth;

  /// Ô vuông nội tiếp vòng trong, chừa khoảng trống nhỏ.
  static Rect get _square {
    final half = (_inner - 8) / math.sqrt2;
    return Rect.fromCenter(center: _center, width: half * 2, height: half * 2);
  }

  void _start(Offset local) {
    final distance = (local - _center).distance;
    if (distance >= _inner - 4 && distance <= _outer + 6) {
      _target = _RingTarget.ring;
    } else if (_square.inflate(8).contains(local)) {
      _target = _RingTarget.square;
    } else {
      _target = _RingTarget.none;
    }
    _update(local);
  }

  void _update(Offset local) {
    switch (_target) {
      case _RingTarget.none:
        return;
      case _RingTarget.ring:
        final vector = local - _center;
        var degrees = math.atan2(vector.dy, vector.dx) * 180 / math.pi;
        if (degrees < 0) degrees += 360;
        widget.onChanged(widget.hsv.withHue(degrees));
      case _RingTarget.square:
        final square = _square;
        final saturation = ((local.dx - square.left) / square.width).clamp(
          0.0,
          1.0,
        );
        final value = (1 - (local.dy - square.top) / square.height).clamp(
          0.0,
          1.0,
        );
        widget.onChanged(
          widget.hsv.withSaturation(saturation).withValue(value),
        );
    }
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    key: const ValueKey('color-panel-wheel'),
    // The panel sits in a scrollable sheet; claim the pointer immediately so
    // a vertical drag on the square picks a value instead of scrolling.
    gestures: {
      _EagerPanGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<_EagerPanGestureRecognizer>(
            _EagerPanGestureRecognizer.new,
            (recognizer) {
              recognizer
                ..onDown = ((details) => _start(details.localPosition))
                ..onUpdate = ((details) => _update(details.localPosition))
                ..onEnd = ((_) => _target = _RingTarget.none);
            },
          ),
    },
    child: CustomPaint(
      size: const Size.square(_HueRingPicker.size),
      painter: _HueRingPainter(widget.hsv, _square),
    ),
  );
}

class _EagerPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _HueRingPainter extends CustomPainter {
  _HueRingPainter(this.hsv, this.square);

  final HSVColor hsv;
  final Rect square;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - _HueRingPicker.ringWidth / 2;
    final ringRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _HueRingPicker.ringWidth
        ..shader = SweepGradient(
          colors: [
            for (var hue = 0; hue <= 360; hue += 60)
              HSVColor.fromAHSV(1, hue % 360.0, 1, 1).toColor(),
          ],
        ).createShader(ringRect),
    );

    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas
      ..drawRect(
        square,
        Paint()
          ..shader = LinearGradient(
            colors: [Colors.white, hueColor],
          ).createShader(square),
      )
      ..drawRect(
        square,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black],
          ).createShader(square),
      );

    final marker = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white;
    final markerShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..color = Colors.black38;
    final angle = hsv.hue * math.pi / 180;
    final ringPoint =
        center + Offset(math.cos(angle), math.sin(angle)) * radius;
    final squarePoint = Offset(
      square.left + hsv.saturation * square.width,
      square.top + (1 - hsv.value) * square.height,
    );
    for (final point in [ringPoint, squarePoint]) {
      canvas
        ..drawCircle(point, 7, markerShadow)
        ..drawCircle(point, 7, marker);
    }
  }

  @override
  bool shouldRepaint(covariant _HueRingPainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    final light = Paint()..color = const Color(0xffffffff);
    final dark = Paint()..color = const Color(0xffd6d6d6);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final even = ((x / cell).floor() + (y / cell).floor()).isEven;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), even ? light : dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter oldDelegate) => false;
}

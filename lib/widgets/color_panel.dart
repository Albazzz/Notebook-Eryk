import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Màu mẫu cố định của bảng màu (hàng swatch đầu tiên).
const colorPanelPresets = <Color>[
  Color(0xff1f2633),
  Color(0xff000000),
  Color(0xff5f6368),
  Color(0xff758ab4),
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

/// Bảng màu gọn: màu mẫu + màu gần đây, thanh độ đậm và các điều khiển
/// riêng của công cụ ([sideChildren]) ở cột trái; vòng sắc độ quanh ô bão
/// hòa/độ sáng ở cột phải. Màn hẹp thì xếp dọc.
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
    this.sideChildren = const [],
    this.wheelSize = 220,
  });

  final Color color;
  final double opacity;
  final void Function(Color color, double opacity) onChanged;
  final List<Color> recentColors;
  final double minOpacity;
  final double maxOpacity;
  final String opacityLabel;

  /// Điều khiển thêm đặt dưới thanh độ đậm (độ dày, làm mượt, xem trước...).
  final List<Widget> sideChildren;
  final double wheelSize;

  @override
  State<ColorPanel> createState() => _ColorPanelState();
}

class _ColorPanelState extends State<ColorPanel> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color.withValues(alpha: 1));
  late double _opacity = widget.opacity.clamp(
    widget.minOpacity,
    widget.maxOpacity,
  );

  Color get _color => _hsv.toColor();

  void _emit() => widget.onChanged(_color, _opacity);

  void _setHsv(HSVColor value) {
    setState(() => _hsv = value);
    _emit();
  }

  void _setColor(Color color) {
    final next = HSVColor.fromColor(color.withValues(alpha: 1));
    // Grey has no hue; keep the current one so the ring marker stays put.
    _setHsv(next.saturation == 0 ? next.withHue(_hsv.hue) : next);
  }

  Widget _opacityRow(Color color) => Row(
    children: [
      SizedBox(
        width: 64,
        child: Text(
          widget.opacityLabel,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
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
        width: 44,
        child: Text(
          '${(_opacity * 100).round()}%',
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color;
    final controls = <Widget>[
      _SwatchRow(colors: colorPanelPresets, selected: color, onTap: _setColor),
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
      const SizedBox(height: 12),
      _opacityRow(color),
      ...widget.sideChildren,
    ];
    final wheel = _HueRingPicker(
      hsv: _hsv,
      size: widget.wheelSize,
      onChanged: _setHsv,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < widget.wheelSize + 260) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...controls.take(widget.recentColors.isEmpty ? 1 : 4),
              const SizedBox(height: 12),
              Center(child: wheel),
              ...controls.skip(widget.recentColors.isEmpty ? 1 : 4),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: controls,
              ),
            ),
            const SizedBox(width: 20),
            wheel,
          ],
        );
      },
    );
  }
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
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final color in colors)
          GestureDetector(
            key: ValueKey('swatch-${color.toARGB32()}'),
            onTap: () => onTap(color),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: color.toARGB32() == selected.toARGB32()
                      ? scheme.primary
                      : scheme.outline.withValues(alpha: .4),
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
  const _HueRingPicker({
    required this.hsv,
    required this.onChanged,
    required this.size,
  });

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  final double size;

  static const ringWidth = 20.0;

  @override
  State<_HueRingPicker> createState() => _HueRingPickerState();
}

enum _RingTarget { none, ring, square }

class _HueRingPickerState extends State<_HueRingPicker> {
  _RingTarget _target = _RingTarget.none;

  Offset get _center => Offset(widget.size / 2, widget.size / 2);
  double get _outer => widget.size / 2;
  double get _inner => _outer - _HueRingPicker.ringWidth;

  /// Ô vuông nội tiếp vòng trong, chừa khoảng trống nhỏ.
  Rect get _square {
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
      size: Size.square(widget.size),
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
      oldDelegate.hsv != hsv || oldDelegate.square != square;
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

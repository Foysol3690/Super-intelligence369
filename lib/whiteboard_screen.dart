import 'package:flutter/material.dart';

class WhiteboardScreen extends StatefulWidget {
  const WhiteboardScreen({super.key});

  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  final List<List<Offset>> _strokes = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101018),
        title: const Text('Maya Whiteboard'),
        actions: [
          IconButton(
            tooltip: 'Clear board',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(_strokes.clear),
          ),
        ],
      ),
      body: GestureDetector(
        onPanStart: (details) =>
            setState(() => _strokes.add([details.localPosition])),
        onPanUpdate: (details) =>
            setState(() => _strokes.last.add(details.localPosition)),
        child: CustomPaint(
          painter: _BoardPainter(_strokes),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  const _BoardPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE8E8E3)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final ink = Paint()
      ..color = const Color(0xFF2783DE)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) => true;
}

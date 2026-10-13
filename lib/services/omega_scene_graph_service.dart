import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Privacy-bounded semantic representation of the current visible UI.
///
/// This service stores labels, relationships and confidence—not screenshots.
/// Pixel models and Accessibility can both contribute observations, but each
/// source remains visible so MAYA never presents an inference as a fact.
class MayaOmegaSceneGraphService {
  static const _storage = FlutterSecureStorage();
  static const _key = 'maya_omega_v9_scene_graph_v1';

  Future<Map<String, dynamic>> ingest({
    required String app,
    required List<dynamic> textNodes,
    required List<dynamic> objects,
    required List<dynamic> intentHints,
    String source = 'accessibility',
    bool captureActive = false,
  }) async {
    final cleanApp = app.trim();
    final now = DateTime.now().toUtc().toIso8601String();
    final previous = await _read();
    final graph = <String, dynamic>{
      'version': 1,
      'observedAt': now,
      'app': cleanApp.isEmpty ? 'unknown' : cleanApp,
      'source': source.trim().isEmpty ? 'unknown' : source.trim(),
      'captureActive': captureActive,
      'textNodes': _boundedNodes(textNodes, 120),
      'objects': _boundedNodes(objects, 80),
      'intentHints': _boundedStrings(intentHints, 12),
      'depth': {
        'mode': 'not_applicable_for_2d_ui',
        'confidence': 1.0,
      },
      'provenance': {
        'pixelsPersisted': false,
        'semanticGraphOnly': true,
      },
    };
    final changes = _diff(previous, graph);
    graph['changes'] = changes;
    await _storage.write(key: _key, value: jsonEncode(graph));
    return {
      'success': true,
      'sceneGraph': graph,
      'changeCount': changes.length,
      'message':
          'Scene graph updated from declared observations; no hidden inference was added.',
    };
  }

  Future<Map<String, dynamic>> ingestAccessibilityTree(
    dynamic raw, {
    bool captureActive = false,
  }) async {
    dynamic decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return {
          'success': false,
          'error': 'Android returned an unreadable Accessibility tree.',
        };
      }
    }
    if (decoded is! Map) {
      return {
        'success': false,
        'error': 'Android Accessibility tree is unavailable.',
      };
    }
    final root = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    if (root['status'] != 'ok') {
      return {
        'success': false,
        'error': root['message']?.toString() ??
            'Android exposed no active Accessibility window.',
        'status': root['status'],
      };
    }
    final textNodes = <Map<String, dynamic>>[];
    final objects = <Map<String, dynamic>>[];
    _flattenAccessibilityNode(
      root['tree'],
      textNodes: textNodes,
      objects: objects,
      depth: 0,
    );
    return ingest(
      app: root['packageName']?.toString() ?? 'unknown',
      textNodes: textNodes,
      objects: objects,
      intentHints: const <String>[],
      source: 'android_accessibility',
      captureActive: captureActive,
    );
  }

  Future<Map<String, dynamic>> snapshot() async {
    final graph = await _read();
    return {
      'success': true,
      'available': graph.isNotEmpty,
      'sceneGraph': graph,
    };
  }

  Future<void> clear() => _storage.delete(key: _key);

  static List<Map<String, dynamic>> _boundedNodes(
    List<dynamic> input,
    int limit,
  ) {
    return input
        .take(limit)
        .map((raw) {
          final item = raw is Map
              ? raw.map((key, value) => MapEntry(key.toString(), value))
              : <String, dynamic>{'label': raw.toString()};
          final confidence = _confidence(item['confidence']);
          return <String, dynamic>{
            'id': item['id']?.toString() ??
                'node_${DateTime.now().microsecondsSinceEpoch}_${item.hashCode}',
            'label': (item['label'] ?? item['text'] ?? item['name'] ?? '')
                .toString()
                .trim(),
            if (item['role'] != null) 'role': item['role'].toString(),
            if (item['bounds'] != null) 'bounds': item['bounds'],
            'confidence': confidence,
          };
        })
        .where((item) => item['label'].toString().isNotEmpty)
        .toList();
  }

  static List<String> _boundedStrings(List<dynamic> input, int limit) => input
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .take(limit)
      .toList();

  static double _confidence(dynamic value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return (parsed ?? 0.5).clamp(0.0, 1.0).toDouble();
  }

  static List<Map<String, dynamic>> _diff(
    Map<String, dynamic> previous,
    Map<String, dynamic> current,
  ) {
    if (previous.isEmpty) {
      return [
        {
          'type': 'scene_started',
          'value': current['app'],
          'confidence': 1.0,
        },
      ];
    }
    final changes = <Map<String, dynamic>>[];
    if (previous['app'] != current['app']) {
      changes.add({
        'type': 'app_changed',
        'from': previous['app'],
        'to': current['app'],
        'confidence': 1.0,
      });
    }
    final oldText = _labels(previous['textNodes']);
    final newText = _labels(current['textNodes']);
    for (final added in newText.difference(oldText).take(20)) {
      changes.add({
        'type': 'text_appeared',
        'value': added,
        'confidence': 0.8,
      });
    }
    for (final removed in oldText.difference(newText).take(20)) {
      changes.add({
        'type': 'text_disappeared',
        'value': removed,
        'confidence': 0.8,
      });
    }
    return changes;
  }

  static Set<String> _labels(dynamic raw) {
    if (raw is! List) return <String>{};
    return raw
        .whereType<Map>()
        .map((item) => item['label']?.toString().toLowerCase().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  static void _flattenAccessibilityNode(
    dynamic raw, {
    required List<Map<String, dynamic>> textNodes,
    required List<Map<String, dynamic>> objects,
    required int depth,
  }) {
    if (raw is! Map || depth > 10 || textNodes.length + objects.length >= 200) {
      return;
    }
    final node = raw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final text = node['text']?.toString().trim() ?? '';
    final description = node['contentDescription']?.toString().trim() ?? '';
    final label = text.isNotEmpty ? text : description;
    final role = node['className']?.toString().split('.').last ?? 'view';
    if (label.isNotEmpty) {
      textNodes.add({
        'id': node['viewId']?.toString().isNotEmpty == true
            ? node['viewId'].toString()
            : 'accessibility_${depth}_${textNodes.length}',
        'label': label,
        'role': role,
        'bounds': node['bounds'],
        'confidence': 1.0,
      });
    } else if (node['isClickable'] == true ||
        node['isEditable'] == true ||
        node['isScrollable'] == true) {
      objects.add({
        'id': node['viewId']?.toString().isNotEmpty == true
            ? node['viewId'].toString()
            : 'control_${depth}_${objects.length}',
        'label': role,
        'role': node['isEditable'] == true
            ? 'editable'
            : node['isScrollable'] == true
                ? 'scrollable'
                : 'clickable',
        'bounds': node['bounds'],
        'confidence': 1.0,
      });
    }
    final children = node['children'];
    if (children is List) {
      for (final child in children) {
        _flattenAccessibilityNode(
          child,
          textNodes: textNodes,
          objects: objects,
          depth: depth + 1,
        );
        if (textNodes.length + objects.length >= 200) break;
      }
    }
  }

  Future<Map<String, dynamic>> _read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {}
    return <String, dynamic>{};
  }
}

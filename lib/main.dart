import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Custom Field Compare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const CustomFieldComparePage(),
    );
  }
}

class CustomFieldComparePage extends StatefulWidget {
  const CustomFieldComparePage({super.key});

  @override
  State<CustomFieldComparePage> createState() => _CustomFieldComparePageState();
}

class _CustomFieldComparePageState extends State<CustomFieldComparePage> {
  final Map<String, List<CustomField>> _sandboxFields = {};
  final Map<String, List<CustomField>> _productionFields = {};
  String? _sandboxFileName;
  String? _productionFileName;
  double _summaryHeight = 280;

  void _handleSummaryDragUpdate(DragUpdateDetails details) {
    setState(() {
      _summaryHeight = (_summaryHeight - details.delta.dy).clamp(140.0, 600.0);
    });
  }

  Future<void> _loadJsonFile(bool isSandbox) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final pickedFile = result.files.single;

    if (pickedFile.bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The selected file could not be read.')),
      );
      return;
    }

    final jsonString = utf8.decode(pickedFile.bytes!);
    await _applyJsonContent(jsonString, isSandbox, pickedFile.name);
  }

  Future<void> _applyJsonContent(String jsonString, bool isSandbox, String displayName) async {
    final decoded = jsonDecode(jsonString);
    final rawItems = _extractItems(decoded);
    final grouped = _groupFieldsByEntityType(rawItems);

    if (!mounted) return;

    setState(() {
      if (isSandbox) {
        _sandboxFields
          ..clear()
          ..addAll(grouped);
        _sandboxFileName = displayName;
      } else {
        _productionFields
          ..clear()
          ..addAll(grouped);
        _productionFileName = displayName;
      }
    });
  }

  List<dynamic> _extractItems(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (decoded['items'] is List) {
        return decoded['items'] as List<dynamic>;
      }
      if (decoded['customFields'] is List) {
        return decoded['customFields'] as List<dynamic>;
      }
      return decoded.values.whereType<List<dynamic>>().firstOrNull ?? const <dynamic>[];
    }

    if (decoded is List) {
      return decoded;
    }

    return const <dynamic>[];
  }

  String _resolveEntityName(Map<String, dynamic> item) {
    final entityType = item['entityType'];

    if (entityType is Map) {
      final name = entityType['name'];
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString();
      }
    }

    if (entityType is List && entityType.isNotEmpty) {
      final first = entityType.first;
      if (first is Map && first['name'] != null) {
        return first['name'].toString();
      }
    }

    final candidates = [
      item['entityTypeName'],
      item['entityName'],
      item['entity'],
      item['entityType']?.toString(),
    ];

    for (final candidate in candidates) {
      if (candidate != null && candidate.toString().trim().isNotEmpty) {
        return candidate.toString();
      }
    }

    return 'Uncategorized';
  }

  Map<String, List<CustomField>> _groupFieldsByEntityType(List<dynamic> rawItems) {
    final grouped = <String, List<CustomField>>{};

    for (final item in rawItems) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final entityName = _resolveEntityName(item);
      final field = CustomField.fromJson(item);
      grouped.putIfAbsent(entityName, () => []).add(field);
    }

    final sortedEntries = grouped.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    return Map<String, List<CustomField>>.fromEntries(sortedEntries);
  }

  Map<String, Map<String, CustomField>> _buildFieldIndex(Map<String, List<CustomField>> source) {
    final index = <String, Map<String, CustomField>>{};

    for (final entry in source.entries) {
      final entityName = entry.key;
      final entityFields = <String, CustomField>{};

      for (final field in entry.value) {
        entityFields[field.name] = field;
      }

      index[entityName] = entityFields;
    }

    return index;
  }

  bool _fieldsDiffer(CustomField left, CustomField right) {
    return left.fieldType != right.fieldType ||
        left.isSystem != right.isSystem ||
        left.required != right.required;
  }

  Widget _buildComparisonSummary() {
    final leftIndex = _buildFieldIndex(_sandboxFields);
    final rightIndex = _buildFieldIndex(_productionFields);

    if (_sandboxFields.isEmpty || _productionFields.isEmpty) {
      return const SizedBox.shrink();
    }

    final allEntities = <String>{
      ...leftIndex.keys,
      ...rightIndex.keys,
    }.toList()..sort();

    final sections = <Widget>[];

    for (final entityName in allEntities) {
      final leftFields = leftIndex[entityName] ?? const <String, CustomField>{};
      final rightFields = rightIndex[entityName] ?? const <String, CustomField>{};

      final onlyLeft = leftFields.keys
          .where((fieldName) => !rightFields.containsKey(fieldName))
          .toList()
        ..sort();
      final onlyRight = rightFields.keys
          .where((fieldName) => !leftFields.containsKey(fieldName))
          .toList()
        ..sort();
      final changed = leftFields.keys
          .where((fieldName) =>
              rightFields.containsKey(fieldName) &&
              _fieldsDiffer(leftFields[fieldName]!, rightFields[fieldName]!))
          .toList()
        ..sort();

      if (onlyLeft.isEmpty && onlyRight.isEmpty && changed.isEmpty) {
        continue;
      }

      final rows = <Widget>[];

      if (onlyLeft.isNotEmpty) {
        rows.add(_buildDifferenceSection('Only in left', onlyLeft, leftFields));
      }
      if (onlyRight.isNotEmpty) {
        rows.add(_buildDifferenceSection('Only in right', onlyRight, rightFields));
      }
      if (changed.isNotEmpty) {
        rows.add(_buildDifferenceSection('Different', changed, leftFields, rightFields));
      }

      sections.add(
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entityName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ...rows,
            ],
          ),
        ),
      );
    }

    if (sections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No differences found between the loaded JSON files.'),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: sections,
      ),
    );
  }

  Widget _buildDifferenceSection(
    String title,
    List<String> fieldNames,
    Map<String, CustomField> leftFields, [
    Map<String, CustomField>? rightFields,
  ]) {
    final color = switch (title) {
      'Only in left' => Colors.green.shade50,
      'Only in right' => Colors.blue.shade50,
      'Different' => Colors.orange.shade50,
      _ => Colors.grey.shade50,
    };

    final borderColor = switch (title) {
      'Only in left' => Colors.green,
      'Only in right' => Colors.blue,
      'Different' => Colors.orange,
      _ => Colors.grey,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: borderColor,
            ),
          ),
          const SizedBox(height: 4),
          ...fieldNames.map((fieldName) {
            final leftField = leftFields[fieldName];
            final rightField = rightFields?[fieldName];

            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor.withValues(alpha: 0.7)),
              ),
              child: Text(
                fieldName +
                    (leftField != null && rightField != null
                        ? ' — left: ${leftField.fieldType}/${leftField.required}/${leftField.isSystem} | right: ${rightField.fieldType}/${rightField.required}/${rightField.isSystem}'
                        : ' — ${leftField != null ? 'left: ${leftField.fieldType}/${leftField.required}/${leftField.isSystem}' : 'right: ${rightField!.fieldType}/${rightField.required}/${rightField.isSystem}'}'),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPanel({
    required String title,
    required Map<String, List<CustomField>> items,
    required String? fileName,
    required bool isSandbox,
  }) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _loadJsonFile(isSandbox),
                  icon: const Icon(Icons.upload_file),
                  label: Text(isSandbox ? 'Load Sandbox JSON' : 'Load Production JSON'),
                ),
              ],
            ),
          ),
          if (fileName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Loaded: $fileName',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('No file loaded'),
                  )
                : ListView(
                    padding: const EdgeInsets.all(8),
                    children: items.entries.map((entry) {
                      final entityName = entry.key;
                      final fields = entry.value;

                      return Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          key: ValueKey(entityName),
                          initiallyExpanded: true,
                          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          childrenPadding: const EdgeInsets.only(left: 20, right: 8, bottom: 8),
                          title: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              entityName,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          children: fields.map((field) {
                            return Padding(
                              padding: const EdgeInsets.only(left: 14, bottom: 4),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: Theme.of(context).colorScheme.primary,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: ListTile(
                                  dense: true,
                                  visualDensity: const VisualDensity(vertical: -2),
                                  contentPadding: const EdgeInsets.only(left: 16, right: 12),
                                  title: Text(field.name),
                                  subtitle: Text(
                                    'Type: ${field.fieldType} • System: ${field.isSystem} • Required: ${field.required}',
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Field Comparison'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _buildPanel(
                    title: 'Sandbox',
                    items: _sandboxFields,
                    fileName: _sandboxFileName,
                    isSandbox: true,
                  ),
                ),
                Expanded(
                  child: _buildPanel(
                    title: 'Production',
                    items: _productionFields,
                    fileName: _productionFileName,
                    isSandbox: false,
                  ),
                ),
              ],
            ),
          ),
          if (_sandboxFields.isNotEmpty && _productionFields.isNotEmpty)
            Column(
              children: [
                GestureDetector(
                  onVerticalDragUpdate: _handleSummaryDragUpdate,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeRow,
                    child: Container(
                      height: 10,
                      width: double.infinity,
                      color: Colors.grey.shade300,
                      child: Center(
                        child: Container(
                          width: 48,
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade600,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Text(
                          'Comparison',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      SizedBox(
                        height: _summaryHeight,
                        child: _buildComparisonSummary(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class CustomField {
  final String name;
  final String fieldType;
  final bool isSystem;
  final bool required;

  const CustomField({
    required this.name,
    required this.fieldType,
    required this.isSystem,
    required this.required,
  });

  factory CustomField.fromJson(Map<String, dynamic> json) {
    return CustomField(
      name: json['name']?.toString() ?? 'Unnamed field',
      fieldType: json['fieldType']?.toString() ?? 'Unknown',
      isSystem: json['isSystem'] == true,
      required: json['required'] == true,
    );
  }
}

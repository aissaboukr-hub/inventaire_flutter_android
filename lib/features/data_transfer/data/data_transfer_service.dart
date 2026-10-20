import 'dart:convert';
import 'dart:typed_data';
import 'package:excel_community/excel_community.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../../../core/data/hive_database.dart';
import '../../product/data/models/product_model.dart';
import '../../product/domain/entities/product.dart';
import '../../billing/domain/entities/cart_item.dart';

/// Progression détaillée d'une opération d'importation.
class ImportProgress {
  final int processed;
  final int total;
  final int imported;
  final int duplicates;
  final int errors;

  const ImportProgress({
    required this.processed,
    required this.total,
    required this.imported,
    required this.duplicates,
    required this.errors,
  });

  double get percentage => total == 0 ? 1 : processed / total;
}

class ImportResult {
  final int imported;
  final int duplicates;
  final int errors;
  final int processed;
  final int total;

  const ImportResult({
    required this.imported,
    required this.duplicates,
    required this.errors,
    required this.processed,
    required this.total,
  });
}

// Exécuté dans un isolate via compute() afin de ne pas bloquer le thread Flutter.
List<List<String>> _decodeExcelRowsInIsolate(List<int> bytes) {
  final workbook = Excel.decodeBytes(bytes);
  if (workbook.tables.isEmpty) throw Exception('Aucune feuille Excel trouvée.');
  final sheet = workbook.tables.values.first;
  if (sheet.rows.isEmpty) throw Exception('Le fichier Excel est vide.');

  String value(CellValue? value) => switch (value) {
        null => '',
        TextCellValue v => v.value.toString(),
        IntCellValue v => v.value.toString(),
        DoubleCellValue v => v.value.toString(),
        BoolCellValue v => v.value.toString(),
        DateCellValue v => v.toString(),
        DateTimeCellValue v => v.toString(),
        TimeCellValue v => v.toString(),
        FormulaCellValue v => v.formula.toString(),
      };

  final rows = <List<String>>[];
  for (var rowIndex = 0; rowIndex < sheet.rows.length; rowIndex++) {
    final row = sheet.rows[rowIndex];
    rows.add(List.generate(4, (i) => i < row.length ? value(row[i]?.value).trim() : ''));
    if (row.length > 4 && row.skip(4).any((cell) => value(cell?.value).trim().isNotEmpty)) {
      rows.last.add('__EXTRA_COLUMN_DATA__');
    }
  }
  return rows;
}

List<List<String>> _parseCsvInIsolate(String text) {
  final rows = <List<String>>[];
  final row = <String>[];
  final cell = StringBuffer();
  bool quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == ',' && !quoted) {
      row.add(cell.toString());
      cell.clear();
    } else if ((ch == '\n' || ch == '\r') && !quoted) {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((v) => v.isNotEmpty)) rows.add(List<String>.from(row));
      row.clear();
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(List<String>.from(row));
  }
  return rows;
}

class DataTransferService {
  static const defaultGoogleSheetsImportUrl =
      'https://docs.google.com/spreadsheets/d/1oa5IjH5EAinCsKtLmOx1VQ8wZd717Ll6/edit?usp=sharing&ouid=116963748618844977648&rtpof=true&sd=true';

  static const List<String> _productImportHeaders = [
    'Code-barres 1',
    'Code-barres 2',
    'Nom',
    'Prix',
  ];

  static void _validateProductHeaders(List<String> headers, {required String source}) {
    final actual = headers.map((h) => h.trim()).toList();
    final valid = actual.length == _productImportHeaders.length &&
        List.generate(_productImportHeaders.length, (i) => actual[i] == _productImportHeaders[i]).every((v) => v);
    if (!valid) {
      throw Exception(
        "Format $source invalide. Le fichier doit contenir exactement ces 4 colonnes, dans cet ordre : Code-barres 1, Code-barres 2, Nom, Prix. Aucune autre colonne n'est autorisée.",
      );
    }
  }

  static String _normalizeBarcode(String value) => value.trim().toUpperCase();

  static Product _productFromRow(List<String> row, {String? id, int stock = 0}) {
    if (row.length < 4) throw Exception('La ligne ne contient pas 4 colonnes.');
    if (row.length > 4) throw Exception('Aucune colonne supplémentaire n’est autorisée.');
    var barcode1 = _normalizeBarcode(row[0]);
    var barcode2 = _normalizeBarcode(row[1]);
    if (barcode1.isEmpty && barcode2.isNotEmpty) {
      barcode1 = barcode2;
      barcode2 = '';
    }
    final name = row[2].trim();
    final priceText = row[3].trim().replaceAll(',', '.');
    if (barcode1.isEmpty) throw Exception('Au moins un code-barres est obligatoire (Code-barres 1 ou Code-barres 2).');
    if (name.isEmpty) throw Exception('Nom est obligatoire.');
    final price = double.tryParse(priceText);
    if (price == null) throw Exception('Prix doit être un nombre.');
    return Product(id: id ?? const Uuid().v4(), name: name, barcode: barcode1, barcode2: barcode2, price: price, stock: stock);
  }

  static Future<List<List<String>>> _readExcelRows(List<int> bytes) async {
    final rows = await compute(_decodeExcelRowsInIsolate, bytes);
    if (rows.isEmpty) throw Exception('Le fichier Excel est vide.');
    _validateProductHeaders(rows.first, source: 'Excel');
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].length > 4) {
        throw Exception('Ligne ${i + 1} invalide dans Excel : aucune colonne supplémentaire n’est autorisée.');
      }
    }
    return rows.skip(1).toList(growable: false);
  }

  static Future<ImportResult> importProductsFromExcel({void Function(ImportProgress)? onProgress}) async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
    if (result == null || result.files.single.bytes == null) return const ImportResult(imported: 0, duplicates: 0, errors: 0, processed: 0, total: 0);
    return _insertProducts(await _readExcelRows(result.files.single.bytes!), onProgress: onProgress);
  }

  static Future<ImportResult> updateProductsFromExcel({void Function(ImportProgress)? onProgress}) async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
    if (result == null || result.files.single.bytes == null) return const ImportResult(imported: 0, duplicates: 0, errors: 0, processed: 0, total: 0);
    return _upsertProducts(await _readExcelRows(result.files.single.bytes!), onProgress: onProgress);
  }

  static Future<List<List<String>>> _readGoogleRows(String link) async {
    final uri = _googleCsvUri(link);
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Impossible de lire Google Sheets. Vérifiez que la feuille est accessible en lecture.');
    }
    final rows = await compute(_parseCsvInIsolate, response.body);
    if (rows.isEmpty) throw Exception('La feuille Google Sheets est vide.');
    _validateProductHeaders(rows.first, source: 'Google Sheets');
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].length > 4 && rows[i].sublist(4).any((cell) => cell.trim().isNotEmpty)) {
        throw Exception("Ligne ${i + 1} invalide dans Google Sheets : aucune colonne supplémentaire n'est autorisée.");
      }
    }
    return rows.skip(1).map((row) => List.generate(4, (i) => i < row.length ? row[i].trim() : '')).toList(growable: false);
  }

  static Future<ImportResult> importProductsFromGoogleSheets(String link, {void Function(ImportProgress)? onProgress}) async =>
      _insertProducts(await _readGoogleRows(link), onProgress: onProgress);

  static Future<ImportResult> updateProductsFromGoogleSheets(String link, {void Function(ImportProgress)? onProgress}) async =>
      _upsertProducts(await _readGoogleRows(link), onProgress: onProgress);

  static Future<ImportResult> _insertProducts(List<List<String>> rows, {void Function(ImportProgress)? onProgress}) async {
    final box = HiveDatabase.productBox;
    final total = rows.length;
    var processed = 0;
    var imported = 0;
    var duplicates = 0;
    var errors = 0;

    // Un seul parcours de la base : les recherches de doublons passent de O(n²) à O(n).
    final barcodeIndex = <String, String>{};
    for (final product in box.values) {
      for (final barcode in product.barcodes) {
        final code = _normalizeBarcode(barcode);
        if (code.isNotEmpty) barcodeIndex.putIfAbsent(code, () => product.id);
      }
    }

    final pending = <String, ProductModel>{};
    final pendingCodes = <String, String>{};

    void report() => onProgress?.call(ImportProgress(processed: processed, total: total, imported: imported, duplicates: duplicates, errors: errors));
    report();

    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (row.every((v) => v.isEmpty)) {
        processed++;
        report();
        continue;
      }
      try {
        final product = _productFromRow(row);
        final incomingCodes = product.barcodes.map(_normalizeBarcode).where((v) => v.isNotEmpty).toSet();
        String? duplicateCode;
        for (final code in incomingCodes) {
          if (barcodeIndex.containsKey(code) || pendingCodes.containsKey(code)) {
            duplicateCode = code;
            break;
          }
        }
        if (duplicateCode != null) {
          duplicates++;
        } else {
          final model = ProductModel.fromEntity(product);
          pending[product.id] = model;
          for (final code in incomingCodes) {
            pendingCodes[code] = product.id;
          }
          imported++;
        }
      } catch (_) {
        errors++;
      }
      processed++;
      report();

      // Ecritures par lots : beaucoup moins d'IO Hive et une UI plus fluide.
      if (pending.length >= 500) {
        await box.putAll(pending);
        barcodeIndex.addAll(pendingCodes.map((k, v) => MapEntry(k, v)));
        pending.clear();
        pendingCodes.clear();
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (pending.isNotEmpty) await box.putAll(pending);
    report();
    return ImportResult(imported: imported, duplicates: duplicates, errors: errors, processed: processed, total: total);
  }

  static Future<ImportResult> _upsertProducts(List<List<String>> rows, {void Function(ImportProgress)? onProgress}) async {
    final box = HiveDatabase.productBox;
    final total = rows.length;
    var processed = 0;
    var imported = 0;
    var duplicates = 0;
    var errors = 0;

    final barcodeIndex = <String, Product>{};
    for (final product in box.values) {
      for (final barcode in product.barcodes) {
        final code = _normalizeBarcode(barcode);
        if (code.isNotEmpty) barcodeIndex.putIfAbsent(code, () => product);
      }
    }

    final pending = <String, ProductModel>{};
    void report() => onProgress?.call(ImportProgress(processed: processed, total: total, imported: imported, duplicates: duplicates, errors: errors));
    report();

    for (final row in rows) {
      if (row.every((v) => v.isEmpty)) {
        processed++;
        report();
        continue;
      }
      try {
        final incoming = _productFromRow(row);
        final incomingCodes = incoming.barcodes.map(_normalizeBarcode).where((v) => v.isNotEmpty).toSet();
        Product? existing;
        for (final code in incomingCodes) {
          final found = barcodeIndex[code];
          if (found != null) {
            if (existing != null && existing.id != found.id) {
              throw Exception('Les codes-barres correspondent à deux produits différents.');
            }
            existing = found;
          }
        }
        final product = existing == null
            ? incoming
            : Product(id: existing.id, name: incoming.name, barcode: incoming.barcode, barcode2: incoming.barcode2, price: incoming.price, stock: existing.stock);
        pending[product.id] = ProductModel.fromEntity(product);
        for (final code in incomingCodes) barcodeIndex[code] = product;
        imported++;
        if (existing != null) duplicates++;
      } catch (_) {
        errors++;
      }
      processed++;
      report();
      if (pending.length >= 500) {
        await box.putAll(pending);
        pending.clear();
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (pending.isNotEmpty) await box.putAll(pending);
    report();
    return ImportResult(imported: imported, duplicates: duplicates, errors: errors, processed: processed, total: total);
  }

  static List<List<String>> _parseCsv(String text) => _parseCsvInIsolate(text);

  static Uri _googleCsvUri(String link) {
    final uri = Uri.parse(link.trim());
    final match = RegExp(r'/spreadsheets/d/([^/]+)').firstMatch(uri.path);
    if (match == null) throw Exception('Lien Google Sheets invalide.');
    final gid = uri.queryParameters['gid'];
    return Uri.parse('https://docs.google.com/spreadsheets/d/${match.group(1)}/gviz/tq').replace(queryParameters: {'tqx': 'out:csv', if (gid != null) 'gid': gid});
  }

  static Uint8List _historyExcelBytes({required List<Map<String, dynamic>> history}) {
    if (history.isEmpty) throw Exception('Aucune opération à exporter.');
    final excel = Excel.createExcel();
    final sheet = excel['Historique'];
    final rows = <List<String>>[
      ['ID', 'Date', 'Type', 'Produit', 'Code-barres', 'Quantité', 'Prix unitaire (DA)', 'Total ligne (DA)', 'Total opération (DA)', 'Devise', 'Erreur'],
    ];
    for (final operation in history) {
      final items = (operation['items'] as List?) ?? const [];
      if (items.isEmpty) {
        rows.add(['${operation['id'] ?? ''}', '${operation['date'] ?? ''}', '${operation['type'] ?? ''}', '', '', '', '', '', '${operation['total'] ?? 0}', '${operation['currency'] ?? 'DZD'}', '${operation['error'] ?? ''}']);
      } else {
        for (final rawItem in items) {
          final item = Map<String, dynamic>.from(rawItem as Map);
          rows.add(['${operation['id'] ?? ''}', '${operation['date'] ?? ''}', '${operation['type'] ?? ''}', '${item['produit'] ?? ''}', '${item['codeBarres'] ?? ''}', '${item['quantite'] ?? 0}', '${item['prixUnitaire'] ?? 0}', '${item['total'] ?? 0}', '${operation['total'] ?? 0}', '${operation['currency'] ?? 'DZD'}', '${operation['error'] ?? ''}']);
        }
      }
    }
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = TextCellValue(rows[r][c]);
      }
    }
    final bytes = excel.encode();
    if (bytes == null) throw Exception('Impossible de générer le fichier Excel.');
    return Uint8List.fromList(bytes);
  }

  static Future<void> exportHistoryToExcel({required List<Map<String, dynamic>> history}) async {
    final bytes = _historyExcelBytes(history: history);
    await FilePicker.saveFile(dialogTitle: 'Exporter l’historique', fileName: 'historique_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx'], bytes: bytes);
  }

  static Future<void> shareHistoryExcel({required List<Map<String, dynamic>> history}) async {
    final bytes = _historyExcelBytes(history: history);
    final fileName = 'historique_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    await Share.shareXFiles([XFile.fromData(bytes, name: fileName, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')], subject: 'Historique des opérations', text: 'Historique des opérations');
  }

  static Future<void> exportHistoryToGoogleSheets({required List<Map<String, dynamic>> history, required String endpoint}) async {
    final url = endpoint.trim();
    if (url.isEmpty) throw Exception('Configurez d’abord l’URL Google Apps Script dans les paramètres.');
    if (history.isEmpty) throw Exception('Aucune opération à synchroniser.');
    final response = await http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'currency': 'DZD', 'history': history})).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Échec de la synchronisation Google Sheets (${response.statusCode}).');
  }
}

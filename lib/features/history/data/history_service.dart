import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../billing/domain/entities/cart_item.dart';
import '../../product/domain/entities/product.dart';
import '../../../core/data/hive_database.dart';

class HistoryService {
  static const boxName = 'stock_movements';
  static const _legacyKey = 'operations_history';
  static const _uuid = Uuid();

  // Compatibilité avec les écrans de facturation conservés dans le code source.
  static List<Map<String, dynamic>> getAll() {
    final raw = HiveDatabase.settingsBox.get(_legacyKey, defaultValue: <dynamic>[]);
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> addSale({required List<CartItem> items, required double total}) async {
    final history = getAll();
    history.insert(0, {'id': _uuid.v4(), 'type': 'Vente', 'date': DateTime.now().toIso8601String(), 'total': total, 'currency': 'DZD', 'items': items.map((item) => {'produit': item.product.name, 'codeBarres': item.product.barcodeDisplay, 'quantite': item.quantity, 'prixUnitaire': item.product.price, 'total': item.total}).toList()});
    await HiveDatabase.settingsBox.put(_legacyKey, history);
  }

  static Future<void> addReturn({required Product product, required int quantity, required double total}) async {
    final history = getAll();
    history.insert(0, {'id': _uuid.v4(), 'type': 'Retour', 'date': DateTime.now().toIso8601String(), 'total': -total, 'currency': 'DZD', 'items': [{'produit': product.name, 'codeBarres': product.barcodeDisplay, 'quantite': quantity, 'prixUnitaire': product.price, 'total': -total}]});
    await HiveDatabase.settingsBox.put(_legacyKey, history);
  }

  static Future<void> addPrintFailure({required List<CartItem> items, required double total, required String error}) async {
    final history = getAll();
    history.insert(0, {'id': _uuid.v4(), 'type': 'Échec impression', 'date': DateTime.now().toIso8601String(), 'total': total, 'currency': 'DZD', 'error': error, 'items': items.map((item) => {'produit': item.product.name, 'codeBarres': item.product.barcodeDisplay, 'quantite': item.quantity, 'prixUnitaire': item.product.price, 'total': item.total}).toList()});
    await HiveDatabase.settingsBox.put(_legacyKey, history);
  }

  static Future<void> clear() async { await HiveDatabase.settingsBox.delete(_legacyKey); await _box.clear(); }

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) await Hive.openBox(boxName);
  }

  static Box get _box => Hive.box(boxName);

  static Future<void> record({
    required String productId,
    required String productName,
    required String type,
    required int quantity,
    required int previousStock,
    required int newStock,
    String reason = '',
  }) async {
    await init();
    await _box.add({
      'productId': productId,
      'productName': productName,
      'type': type,
      'quantity': quantity,
      'previousStock': previousStock,
      'newStock': newStock,
      'reason': reason,
      'date': DateTime.now().toIso8601String(),
    });
  }

  static List<Map<String, dynamic>> all() {
    if (!Hive.isBoxOpen(boxName)) return [];
    final entries = _box.values.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    entries.sort((a, b) => (b['date'] as String? ?? '').compareTo(a['date'] as String? ?? ''));
    return entries;
  }
}

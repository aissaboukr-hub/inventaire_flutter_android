import 'dart:async';
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:permission_handler/permission_handler.dart';

class EscPos {
  static const List<int> init = [0x1B, 0x40];
  static const List<int> alignCenter = [0x1B, 0x61, 0x01];
  static const List<int> alignLeft = [0x1B, 0x61, 0x00];
  static const List<int> alignRight = [0x1B, 0x61, 0x02];
  static const List<int> boldOn = [0x1B, 0x45, 0x01];
  static const List<int> boldOff = [0x1B, 0x45, 0x00];
  static const List<int> textNormal = [0x1D, 0x21, 0x00];
  static const List<int> textLarge = [0x1D, 0x21, 0x11];
  static const List<int> lineFeed = [0x0A];
}

class PrinterHelper {
  static final PrinterHelper _instance = PrinterHelper._internal();
  factory PrinterHelper() => _instance;
  PrinterHelper._internal();

  bool _isConnected = false;
  String? _connectedMac;
  Future<bool>? _connectionOperation;

  bool get isConnected => _isConnected;
  String? get connectedMac => _connectedMac;

  Future<bool> checkPermission() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    return statuses.values.every((status) => status.isGranted);
  }

  Future<List<BluetoothInfo>> getBondedDevices() async {
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return [];
    }
  }

  /// Connexion directe à l'adresse connue. Aucun scan n'est effectué ici.
  Future<bool> connect(String macAddress) async {
    final mac = macAddress.trim();
    if (mac.isEmpty) return false;

    final running = _connectionOperation;
    if (running != null) return running;

    final operation = _connectInternal(mac);
    _connectionOperation = operation;
    try {
      return await operation;
    } finally {
      if (identical(_connectionOperation, operation)) _connectionOperation = null;
    }
  }

  Future<bool> _connectInternal(String mac) async {
    // Une connexion déjà établie est conservée.
    if (_isConnected && _connectedMac == mac) return true;

    try {
      // Un seul appel au plugin : aucune tentative artificielle et aucun timeout
      // ajouté par l'application. Le plugin gère lui-même la connexion native.
      final result = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (result) {
        _isConnected = true;
        _connectedMac = mac;
        return true;
      }
    } catch (_) {
      _isConnected = false;
    }
    return false;
  }

  Future<bool> ensureConnected(String macAddress) async {
    final mac = macAddress.trim();
    if (mac.isEmpty) return false;
    try {
      if (_isConnected && _connectedMac == mac && await PrintBluetoothThermal.connectionStatus) return true;
    } catch (_) {}
    _isConnected = false;
    return connect(mac);
  }

  Future<bool> disconnect() async {
    try {
      final result = await PrintBluetoothThermal.disconnect;
      _isConnected = false;
      _connectedMac = null;
      return result;
    } catch (_) {
      _isConnected = false;
      _connectedMac = null;
      return false;
    }
  }

  Future<bool> isActuallyConnected() async {
    if (!_isConnected) return false;
    try {
      final connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) _isConnected = false;
      return connected;
    } catch (_) {
      _isConnected = false;
      return false;
    }
  }

  Future<void> printText(String text) async {
    if (!await isActuallyConnected()) throw Exception('La connexion à l’imprimante a été perdue.');
    await PrintBluetoothThermal.writeBytes(text.codeUnits);
  }

  static const int _productWidth = 27;
  static const int _unitPriceWidth = 9;
  static const int _totalWidth = 10;

  String _fitRight(String value, int width) {
    if (value.length >= width) return value.substring(value.length - width);
    return value.padLeft(width);
  }

  String _fitLeft(String value, int width) {
    if (value.length >= width) return value.substring(0, width);
    return value.padRight(width);
  }

  List<String> _formatItemLines({
    required String quantity,
    required String name,
    required String unitPrice,
    required String lineTotal,
  }) {
    final product = _fitLeft('$quantity x $name', _productWidth);
    final price = _fitRight(unitPrice, _unitPriceWidth);
    final total = _fitRight(lineTotal, _totalWidth);
    return [
      '$product$price$total',
    ];
  }

  Future<void> printHistory({required List<Map<String, dynamic>> history}) async {
    if (!await isActuallyConnected()) throw Exception('La connexion à l’imprimante a été perdue.');

    final bytes = <int>[...EscPos.init, ...EscPos.alignCenter, ...EscPos.boldOn];
    bytes.addAll(_textToBytes('HISTORIQUE DES OPERATIONS'));
    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(EscPos.boldOff);
    bytes.addAll(_textToBytes('------------------------------------------------'));
    bytes.addAll(EscPos.lineFeed);

    // Même structure que CAISSE ASW : une ligne d'en-tête et des colonnes
    // fixes pour quantité/produit, prix unitaire et total.
    bytes.addAll(EscPos.alignLeft);
    bytes.addAll(_textToBytes(_fitLeft('Qte x Produit', _productWidth) +
        _fitRight('P.U', _unitPriceWidth) +
        _fitRight('Total', _totalWidth)));
    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(_textToBytes('------------------------------------------------'));
    bytes.addAll(EscPos.lineFeed);

    for (final operation in history) {
      final date = operation['date']?.toString() ?? '';
      final type = operation['type']?.toString() ?? 'Opération';
      final total = operation['total']?.toString() ?? '0';
      bytes.addAll(EscPos.boldOn);
      bytes.addAll(_textToBytes('$type | $date'));
      bytes.addAll(EscPos.lineFeed);
      bytes.addAll(EscPos.boldOff);
      bytes.addAll(_textToBytes('TOTAL OPERATION: $total DA'));
      bytes.addAll(EscPos.lineFeed);

      final error = operation['error']?.toString() ?? '';
      if (error.isNotEmpty) {
        bytes.addAll(_textToBytes('ERREUR: $error'));
        bytes.addAll(EscPos.lineFeed);
      }

      final items = (operation['items'] as List?) ?? const [];
      for (final rawItem in items) {
        final item = Map<String, dynamic>.from(rawItem as Map);
        final name = item['produit']?.toString() ?? '';
        final qty = item['quantite']?.toString() ?? '0';
        final unitPrice = item['prixUnitaire']?.toString() ?? item['prix']?.toString() ?? item['price']?.toString() ?? '0';
        final lineTotal = item['total']?.toString() ?? '0';

        for (final line in _formatItemLines(
          quantity: qty,
          name: name,
          unitPrice: unitPrice,
          lineTotal: lineTotal,
        )) {
          bytes.addAll(_textToBytes(line));
          bytes.addAll(EscPos.lineFeed);
        }
      }
      bytes.addAll(_textToBytes('------------------------------------------------'));
      bytes.addAll(EscPos.lineFeed);
    }

    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(EscPos.lineFeed);
    await PrintBluetoothThermal.writeBytes(bytes);
  }

  Future<void> printReceipt({
    required String shopName,
    required String address1,
    required String address2,
    required String phone,
    required List<Map<String, dynamic>> items,
    required double total,
    required String footer,
  }) async {
    if (!await isActuallyConnected()) throw Exception('La connexion à l’imprimante a été perdue.');

    final bytes = <int>[];
    bytes.addAll(EscPos.init);
    bytes.addAll(EscPos.alignCenter);
    bytes.addAll(EscPos.boldOn);
    bytes.addAll(EscPos.textLarge);
    bytes.addAll(_textToBytes(shopName));
    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(EscPos.textNormal);
    bytes.addAll(EscPos.boldOff);
    if (address1.isNotEmpty) {
      bytes.addAll(_textToBytes(address1));
      bytes.addAll(EscPos.lineFeed);
    }
    if (address2.isNotEmpty) {
      bytes.addAll(_textToBytes(address2));
      bytes.addAll(EscPos.lineFeed);
    }
    bytes.addAll(_textToBytes(phone));
    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(_textToBytes(DateFormat('dd-MM-yyyy hh:mm a').format(DateTime.now())));
    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(_textToBytes('------------------------------------------------'));
    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(EscPos.alignLeft);

    // Format commun aux deux tickets : produit, prix unitaire et total.
    bytes.addAll(_textToBytes(_fitLeft('Qte x Produit', _productWidth) +
        _fitRight('P.U', _unitPriceWidth) +
        _fitRight('Total', _totalWidth)));
    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(_textToBytes('------------------------------------------------'));
    bytes.addAll(EscPos.lineFeed);

    for (final item in items) {
      final name = item['name']?.toString() ?? '';
      final quantity = item['qty']?.toString() ?? '0';
      final unitPrice = item['price']?.toString() ?? '0';
      final lineTotal = item['total']?.toString() ?? '0';

      for (final line in _formatItemLines(
        quantity: quantity,
        name: name,
        unitPrice: unitPrice,
        lineTotal: lineTotal,
      )) {
        bytes.addAll(_textToBytes(line));
        bytes.addAll(EscPos.lineFeed);
      }
    }

    bytes.addAll(_textToBytes('------------------------------------------------'));
    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(EscPos.alignRight);
    bytes.addAll(EscPos.boldOn);
    bytes.addAll(_textToBytes('TOTAL: $total DA'));
    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(EscPos.boldOff);
    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(EscPos.alignCenter);
    bytes.addAll(_textToBytes(footer));
    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(EscPos.lineFeed);
    bytes.addAll(EscPos.lineFeed);

    await PrintBluetoothThermal.writeBytes(bytes);
  }

  List<int> _textToBytes(String text) => text.codeUnits;
}

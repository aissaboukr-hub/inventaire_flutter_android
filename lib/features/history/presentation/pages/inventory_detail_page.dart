import 'dart:io';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart' hide Border, BorderStyle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../../../product/domain/entities/product.dart';
import '../../../auth/data/auth_service.dart';
import '../../data/history_service.dart';

const _green = Color(0xFF009B65);
const _dark = Color(0xFF111111);
const _panel = Color(0xFF202126);

class InventoryDetailPage extends StatefulWidget {
  final Map<String, dynamic> session;
  const InventoryDetailPage({super.key, required this.session});
  @override
  State<InventoryDetailPage> createState() => _InventoryDetailPageState();
}

class _InventoryDetailPageState extends State<InventoryDetailPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _scanNotFound = false;
  int? _lastSearchResetToken;

  @override
  void initState() {
    super.initState();
    _lastSearchResetToken = int.tryParse('${widget.session['resetInventorySearch'] ?? ''}');
  }

  @override
  void didUpdateWidget(covariant InventoryDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final token = int.tryParse('${widget.session['resetInventorySearch'] ?? ''}');
    if (token != null && token != _lastSearchResetToken) {
      _lastSearchResetToken = token;
      _searchController.clear();
      _query = '';
      _scanNotFound = false;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _updateCount(Product product, int delta) async {
    final box = Hive.box('inventory_sessions');
    final data = Map<String, dynamic>.from(
      box.get(widget.session['id']) as Map? ?? widget.session,
    );
    final counts = Map<String, dynamic>.from(data['products'] as Map? ?? {});
    final old = int.tryParse('${counts[product.id] ?? 0}') ?? 0;
    final now = DateTime.now().toIso8601String();
    counts[product.id] = old + delta;
    data['products'] = counts;
    final enteredAt = Map<String, dynamic>.from(data['productEntryTimes'] as Map? ?? {});
    // Conserver la date de première saisie du produit dans cet inventaire.
    enteredAt[product.id] = now;
    data['productEntryTimes'] = enteredAt;
    await box.put(data['id'], data);
    await HistoryService.record(
      productId: product.id, productName: product.name, type: 'Saisie inventaire',
      quantity: delta, previousStock: old, newStock: old + delta,
      reason: 'Modification de la quantité saisie',
      inventoryId: '${data['id']}', inventoryName: '${data['name'] ?? 'Inventaire'}',
    );
    if (!mounted) return;
    setState(() {
      widget.session['products'] = counts;
      widget.session['productEntryTimes'] = enteredAt;
    });
  }

  List<int> _buildInventoryExcelBytes(
    List<Product> products,
    Map<String, dynamic> counts,
    Map<String, dynamic> enteredAt,
  ) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    final sheet = excel[defaultSheet ?? 'Inventaire'];
    final title = '${widget.session['name'] ?? 'Inventaire'}';
    final rows = <List<String>>[
      ['Inventaire', title],
      ['Date export', DateTime.now().toLocal().toString().split('.').first],
      [],
      [
        'Nom du produit',
        'Code-barres 1',
        'Code-barres 2',
        'Stock actuel',
        'Écart saisi',
        'Prix (DA)',
        'Date et heure de saisie',
      ],
    ];

    for (final product in products) {
      rows.add([
        product.name,
        product.barcode,
        product.barcode2,
        '${product.stock}',
        '${int.tryParse('${counts[product.id] ?? 0}') ?? 0}',
        product.price == 0 ? '' : product.price.toString(),
        _formatEntryDate(enteredAt[product.id]?.toString()),
      ]);
    }

    final black = ExcelColor.fromHexString('#FF000000');
    final white = ExcelColor.fromHexString('#FFFFFFFF');
    final green = ExcelColor.fromHexString('#FF218C58');
    final thinBorder = Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: black,
    );
    final headerBorder = Border(
      borderStyle: BorderStyle.Medium,
      borderColorHex: black,
    );

    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        final index = CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);
        final value = TextCellValue(rows[r][c]);
        CellStyle? style;

        if (r == 3) {
          style = CellStyle(
            bold: true,
            fontColorHex: white,
            backgroundColorHex: green,
            horizontalAlign: HorizontalAlign.Center,
            verticalAlign: VerticalAlign.Center,
            textWrapping: TextWrapping.WrapText,
            topBorder: headerBorder,
            bottomBorder: headerBorder,
            leftBorder: thinBorder,
            rightBorder: thinBorder,
          );
        } else if (r >= 4) {
          style = CellStyle(
            fontColorHex: black,
            verticalAlign: VerticalAlign.Center,
            textWrapping: TextWrapping.WrapText,
            topBorder: thinBorder,
            bottomBorder: thinBorder,
            leftBorder: thinBorder,
            rightBorder: thinBorder,
          );
        } else if (r < 2) {
          style = CellStyle(
            bold: c == 0,
            fontColorHex: black,
            topBorder: thinBorder,
            bottomBorder: thinBorder,
            leftBorder: thinBorder,
            rightBorder: thinBorder,
          );
        }

        // updateCell writes the value and its style together into the XLSX sheet.
        sheet.updateCell(index, value, cellStyle: style);
      }
    }

    // Keep the header row visible and make the exported sheet easy to read.
    final columnWidths = <int, double>{
      0: 30,
      1: 20,
      2: 20,
      3: 15,
      4: 15,
      5: 15,
      6: 28,
    };
    for (final entry in columnWidths.entries) {
      sheet.setColumnWidth(entry.key, entry.value);
    }
    sheet.setRowHeight(3, 34);

    // Deuxième feuille : historique des mouvements propres à cet inventaire.
    final movementSheet = excel['Historique des mouvements'];
    final inventoryId = '${widget.session['id'] ?? ''}';
    final movementBox = Hive.box('stock_movements');
    final movements = movementBox.values.whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((m) => m['inventoryId'] == inventoryId)
        .toList()
      ..sort((a, b) => (b['date'] as String? ?? '').compareTo(a['date'] as String? ?? ''));
    final movementRows = <List<String>>[
      ['Inventaire', title],
      ['Date export', DateTime.now().toLocal().toString().split('.').first],
      [],
      ['Date et heure', 'Type de mouvement', 'Produit', 'Quantité / écart', 'Valeur précédente', 'Nouvelle valeur', 'Motif'],
      ...movements.map((m) => [
        _formatEntryDate(m['date']?.toString()),
        '${m['type'] ?? ''}',
        '${m['productName'] ?? ''}',
        '${m['quantity'] ?? 0}',
        '${m['previousStock'] ?? 0}',
        '${m['newStock'] ?? 0}',
        '${m['reason'] ?? ''}',
      ]),
    ];
    for (var r = 0; r < movementRows.length; r++) {
      for (var c = 0; c < movementRows[r].length; c++) {
        final idx = CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);
        final val = TextCellValue(movementRows[r][c]);
        CellStyle? style;
        if (r == 3) {
          style = CellStyle(bold: true, fontColorHex: white, backgroundColorHex: green,
            horizontalAlign: HorizontalAlign.Center, verticalAlign: VerticalAlign.Center,
            textWrapping: TextWrapping.WrapText, topBorder: headerBorder, bottomBorder: headerBorder,
            leftBorder: thinBorder, rightBorder: thinBorder);
        } else if (r >= 4 || r < 2) {
          style = CellStyle(bold: r < 2 && c == 0, fontColorHex: black,
            verticalAlign: VerticalAlign.Center, textWrapping: TextWrapping.WrapText,
            topBorder: thinBorder, bottomBorder: thinBorder, leftBorder: thinBorder, rightBorder: thinBorder);
        }
        movementSheet.updateCell(idx, val, cellStyle: style);
      }
    }
    const movementWidths = <int, double>{0: 22, 1: 22, 2: 30, 3: 18, 4: 18, 5: 18, 6: 34};
    for (final entry in movementWidths.entries) { movementSheet.setColumnWidth(entry.key, entry.value); }
    movementSheet.setRowHeight(3, 34);

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Impossible de créer le fichier Excel.');
    return bytes;
  }

  String _safeFilePart(String value) => value
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  String _exportFileName() {
    final inventoryName = _safeFilePart('${widget.session['name'] ?? 'inventaire'}');
    final username = _safeFilePart(AuthService().currentUsername ?? 'utilisateur');
    return '${inventoryName.isEmpty ? 'inventaire' : inventoryName}_${username.isEmpty ? 'utilisateur' : username}.xlsx';
  }

  String _formatEntryDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  Future<void> _shareInventory(List<Product> products, Map<String, dynamic> counts, Map<String, dynamic> enteredAt) async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun produit saisi à exporter.')));
      return;
    }
    try {
      final bytes = Uint8List.fromList(_buildInventoryExcelBytes(products, counts, enteredAt));
      final name = _exportFileName();

      // Share a real temporary file. XFile.fromData may be exposed by Android
      // with an automatically generated UUID instead of the requested name.
      final exportDirectory = await Directory.systemTemp.createTemp('inventaire_export_');
      final exportFile = File('${exportDirectory.path}/$name');
      await exportFile.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(exportFile.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        subject: 'Inventaire : ${widget.session['name'] ?? 'Inventaire'}',
        text: 'Liste de l’inventaire ${widget.session['name'] ?? ''}',
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec du partage : $e')));
    }
  }

  bool _matches(Product product, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    return product.name.toLowerCase().contains(q) ||
        product.barcodes.any((barcode) => barcode.toLowerCase().contains(q));
  }

  Future<void> _scan() async {
    final code = await context.push<String>('/scanner');
    if (!mounted || code == null || code.trim().isEmpty) return;
    final scannedCode = code.trim();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _searchController.text = scannedCode;
    final state = context.read<ProductBloc>().state;
    final found = state.products.any((product) => product.barcodes.any(
          (barcode) => barcode.toLowerCase() == scannedCode.toLowerCase(),
        ));
    setState(() {
      _query = scannedCode;
      _scanNotFound = !found;
    });
    if (!found) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aucun produit trouvé pour le code-barres : $scannedCode'),
          action: SnackBarAction(
            label: 'Effacer',
            onPressed: () {
              _searchController.clear();
              if (mounted) setState(() { _query = ''; _scanNotFound = false; });
            },
          ),
        ),
      );
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() { _query = ''; _scanNotFound = false; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _dark,
        appBar: AppBar(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          title: Text(widget.session['name'] ?? 'Inventaire',
              overflow: TextOverflow.ellipsis),
          actions: [
            PopupMenuButton<String>(
              iconColor: Colors.white,
              onSelected: (v) async {
                if (v == 'history') {
                  context.push('/history', extra: widget.session);
                } else {
                  final state = context.read<ProductBloc>().state;
                  final counts = Map<String, dynamic>.from(widget.session['products'] as Map? ?? {});
                  final enteredAt = Map<String, dynamic>.from(widget.session['productEntryTimes'] as Map? ?? {});
                  final products = state.products.where((p) => counts.containsKey(p.id)).toList()
                    ..sort((a, b) {
                      final da = DateTime.tryParse('${enteredAt[a.id] ?? ''}') ?? DateTime.tryParse('${widget.session['createdAt'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
                      final db = DateTime.tryParse('${enteredAt[b.id] ?? ''}') ?? DateTime.tryParse('${widget.session['createdAt'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
                      return db.compareTo(da);
                    });
                  if (v == 'share') await _shareInventory(products, counts, enteredAt);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share), title: Text('Partager Excel (WhatsApp / Bluetooth)'), contentPadding: EdgeInsets.zero)),
                PopupMenuItem(value: 'history', child: ListTile(leading: Icon(Icons.history), title: Text('Historique des mouvements'), contentPadding: EdgeInsets.zero)),
              ],
            ),
          ],
        ),
        body: BlocBuilder<ProductBloc, ProductState>(builder: (context, state) {
          final counts = Map<String, dynamic>.from(
            widget.session['products'] as Map? ?? {},
          );
          final query = _query.trim();
          // Sans recherche, ne montrer que les produits déjà saisis dans cet inventaire.
          // Pendant une recherche manuelle ou après un scan, chercher dans tout le catalogue.
          final products = state.products.where((product) {
            if (query.isEmpty) return counts.containsKey(product.id);
            return _matches(product, query);
          }).toList()
            ..sort((a, b) {
              final enteredAt = Map<String, dynamic>.from(widget.session['productEntryTimes'] as Map? ?? {});
              final created = DateTime.tryParse('${widget.session['createdAt'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
              final da = DateTime.tryParse('${enteredAt[a.id] ?? ''}') ?? created;
              final db = DateTime.tryParse('${enteredAt[b.id] ?? ''}') ?? created;
              return db.compareTo(da);
            });

          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() {
                      _query = value.trim();
                      _scanNotFound = false;
                    }),
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      hintText: 'Rechercher par nom ou code-barres',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: _panel,
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Effacer la recherche',
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.close, color: Colors.white70),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _scan,
                  style: IconButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(52, 52),
                  ),
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Scanner un code-barres',
                ),
              ]),
            ),
            Container(
              width: double.infinity,
              color: _panel,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                query.isEmpty
                    ? '${counts.length} produit(s) saisi(s) dans cet inventaire'
                    : '${products.length} résultat(s) de recherche',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            Expanded(
              child: products.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          query.isEmpty
                              ? 'Aucun produit saisi pour le moment.\nRecherchez un article ou scannez son code-barres pour commencer.'
                              : (_scanNotFound
                                  ? 'Produit absent du catalogue.\nVérifiez le code-barres ou ajoutez le produit au catalogue.'
                                  : 'Aucun article correspondant.\nEssayez un autre nom ou code-barres.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, height: 1.5),
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white24),
                      itemBuilder: (context, i) {
                        final p = products[i];
                        final alreadyEntered = counts.containsKey(p.id);
                        final adjustment = int.tryParse('${counts[p.id] ?? 0}') ?? 0;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 17)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              '${p.barcodeDisplay}\nStock : ${p.stock}${alreadyEntered ? '' : ' • Non saisi'}',
                              style: const TextStyle(color: Colors.white70, height: 1.4),
                            ),
                          ),
                          isThreeLine: true,
                          trailing: SizedBox(
                            width: 100,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  alreadyEntered ? '$adjustment' : '—',
                                  style: TextStyle(color: alreadyEntered ? const Color(0xFF80DDB9) : Colors.white54, fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                Text(alreadyEntered ? 'écart saisi' : 'Rechercher', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                              ],
                            ),
                          ),
                          onTap: () => _showActions(p, adjustment),
                        );
                      },
                    ),
            ),
          ]);
        }),
        floatingActionButton: FloatingActionButton(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          onPressed: () => context.push('/products/add'),
          tooltip: 'Ajouter un produit au catalogue',
          child: const Icon(Icons.add),
        ),
      );

  void _showActions(Product p, int adjustment) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _panel,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Stock actuel : ${p.stock} • Écart saisi : $adjustment', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _green),
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/inventory/quantity', extra: {'session': widget.session, 'product': p, 'type': 'in'}).then((_) {
                        if (mounted) setState(() {});
                      });
                    },
                    icon: const Icon(Icons.arrow_downward),
                    label: const Text('IN  +'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF34353B)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/inventory/quantity', extra: {'session': widget.session, 'product': p, 'type': 'out'}).then((_) {
                        if (mounted) setState(() {});
                      });
                    },
                    icon: const Icon(Icons.arrow_upward),
                    label: const Text('OUT  −'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _updateCount(p, 0);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.fact_check),
                  label: const Text('Marquer / consulter le comptage'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

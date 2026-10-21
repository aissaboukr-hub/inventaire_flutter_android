import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../product/domain/entities/product.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../../data/history_service.dart';

enum StockOperation { entry, exit, count }

class MovementPage extends StatefulWidget {
  final StockOperation initialOperation;
  const MovementPage({super.key, required this.initialOperation});
  @override
  State<MovementPage> createState() => _MovementPageState();
}

class _MovementPageState extends State<MovementPage> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _newNameController = TextEditingController();
  final _newPriceController = TextEditingController();
  String? _productId;
  String _scannedBarcode = '';
  bool _showNewProduct = false;
  late StockOperation _operation;
  bool _saving = false;

  @override
  void initState() { super.initState(); _operation = widget.initialOperation; }
  @override
  void dispose() {
    _quantityController.dispose(); _reasonController.dispose(); _barcodeController.dispose();
    _newNameController.dispose(); _newPriceController.dispose(); super.dispose();
  }

  String get _title => switch (_operation) { StockOperation.entry => 'Entrée de stock', StockOperation.exit => 'Sortie de stock', StockOperation.count => 'Inventaire physique' };

  Future<void> _scan(List<Product> products) async {
    final result = await context.push<String>('/scanner');
    if (!mounted || result == null || result.trim().isEmpty) return;
    final code = result.trim();
    final product = products.where((p) => p.barcodes.any((b) => b.toUpperCase() == code.toUpperCase())).firstOrNull;
    setState(() {
      _scannedBarcode = code;
      _barcodeController.text = code;
      _productId = product?.id;
      _showNewProduct = product == null && _operation == StockOperation.count;
    });
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_operation == StockOperation.count ? 'Produit introuvable : saisissez son nom et son prix pour l’ajouter.' : 'Produit introuvable dans le catalogue.')));
    }
  }

  Future<void> _save(List<Product> products) async {
    if (!_formKey.currentState!.validate()) return;
    final value = int.parse(_quantityController.text.trim());
    if (_showNewProduct && _operation == StockOperation.count) {
      final name = _newNameController.text.trim();
      final price = double.tryParse(_newPriceController.text.replaceAll(',', '.'));
      if (name.isEmpty || price == null || price < 0 || _scannedBarcode.isEmpty) return;
      final duplicate = products.where((p) => p.barcodes.any((b) => b.toUpperCase() == _scannedBarcode.toUpperCase())).firstOrNull;
      if (duplicate != null) { setState(() { _productId = duplicate.id; _showNewProduct = false; }); return; }
      if (value < 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La quantité initiale du nouveau produit doit être positive ou nulle.'))); return; }
      setState(() => _saving = true);
      try {
        final product = Product(id: const Uuid().v4(), name: name, barcode: _scannedBarcode, price: price, stock: value);
        context.read<ProductBloc>().add(AddProduct(product));
        await HistoryService.record(productId: product.id, productName: product.name, type: 'Inventaire', quantity: value, previousStock: 0, newStock: value, reason: _reasonController.text.trim().isEmpty ? 'Création depuis inventaire physique' : _reasonController.text.trim());
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produit ajouté et inventaire enregistré.')));
        context.pop();
      } finally { if (mounted) setState(() => _saving = false); }
      return;
    }
    final product = products.where((p) => p.id == _productId).firstOrNull;
    if (product == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scannez ou choisissez un produit.'))); return; }
    // En inventaire physique, la valeur est un ajustement (+/-), pas le stock total compté.
    final newStock = _operation == StockOperation.entry ? product.stock + value : _operation == StockOperation.exit ? product.stock - value : product.stock + value;
    if (_operation == StockOperation.exit && value > product.stock) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock insuffisant pour cette sortie.'))); return; }
    if (newStock < 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le stock ne peut pas devenir négatif.'))); return; }
    setState(() => _saving = true);
    final type = _operation == StockOperation.entry ? 'Entrée' : _operation == StockOperation.exit ? 'Sortie' : 'Inventaire';
    try {
      await HistoryService.record(productId: product.id, productName: product.name, type: type, quantity: value.abs(), previousStock: product.stock, newStock: newStock, reason: _reasonController.text.trim());
      if (!mounted) return;
      context.read<ProductBloc>().add(UpdateProduct(Product(id: product.id, name: product.name, barcode: product.barcode, barcode2: product.barcode2, price: product.price, stock: newStock)));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mouvement enregistré.')));
      context.pop();
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_title)),
    body: BlocBuilder<ProductBloc, ProductState>(builder: (context, state) {
      final products = state.products;
      final selected = products.where((p) => p.id == _productId).firstOrNull;
      return Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(20), children: [
        SegmentedButton<StockOperation>(segments: const [ButtonSegment(value: StockOperation.entry, label: Text('Entrée'), icon: Icon(Icons.add)), ButtonSegment(value: StockOperation.exit, label: Text('Sortie'), icon: Icon(Icons.remove)), ButtonSegment(value: StockOperation.count, label: Text('Inventaire'), icon: Icon(Icons.fact_check))], selected: {_operation}, onSelectionChanged: (v) => setState(() { _operation = v.first; _quantityController.clear(); _showNewProduct = false; })),
        const SizedBox(height: 20),
        Row(children: [Expanded(child: TextFormField(controller: _barcodeController, decoration: const InputDecoration(labelText: 'Code-barres', prefixIcon: Icon(Icons.qr_code)), onChanged: (code) { final p = products.where((p) => p.barcodes.any((b) => b.toUpperCase() == code.trim().toUpperCase())).firstOrNull; setState(() { _productId = p?.id; _scannedBarcode = code.trim(); _showNewProduct = p == null && code.trim().isNotEmpty && _operation == StockOperation.count; }); })), IconButton.filledTonal(tooltip: 'Scanner un produit', onPressed: () => _scan(products), icon: const Icon(Icons.qr_code_scanner))]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _productId, isExpanded: true, decoration: const InputDecoration(labelText: 'Produit existant', prefixIcon: Icon(Icons.inventory_2_outlined)), items: products.map((p) => DropdownMenuItem(value: p.id, child: Text('${p.name} • stock : ${p.stock}', overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() { _productId = v; _showNewProduct = false; }), validator: (v) => !_showNewProduct && v == null ? 'Scannez ou choisissez un produit' : null),
        if (selected != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Stock actuel : ${selected.stock} unité(s)', style: const TextStyle(fontWeight: FontWeight.w600))),
        if (_showNewProduct && _operation == StockOperation.count) ...[
          const SizedBox(height: 18), const Text('Nouveau produit', style: TextStyle(fontWeight: FontWeight.bold)),
          TextFormField(controller: _newNameController, decoration: const InputDecoration(labelText: 'Nom du produit'), validator: (v) => _showNewProduct && (v == null || v.trim().isEmpty) ? 'Saisissez le nom du produit' : null),
          TextFormField(controller: _newPriceController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Prix (DA)'), validator: (v) => _showNewProduct && (double.tryParse((v ?? '').replaceAll(',', '.')) == null || double.parse((v ?? '0').replaceAll(',', '.')) < 0) ? 'Saisissez un prix valide' : null),
        ],
        const SizedBox(height: 18),
        TextFormField(controller: _quantityController, keyboardType: TextInputType.number, inputFormatters: _operation == StockOperation.count ? [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))] : [FilteringTextInputFormatter.digitsOnly], decoration: InputDecoration(labelText: _operation == StockOperation.count ? (_showNewProduct ? 'Quantité initiale' : 'Correction du stock (+/-)') : 'Quantité', helperText: _operation == StockOperation.count && !_showNewProduct ? 'Ex. -2 pour retirer 2 unités, +3 pour ajouter 3.' : null, prefixIcon: const Icon(Icons.numbers)), validator: (v) { final n = int.tryParse((v ?? '').trim()); if (n == null) return 'Saisissez une quantité valide'; if (_operation != StockOperation.count && n <= 0) return 'La quantité doit être supérieure à zéro'; if (_showNewProduct && n < 0) return 'La quantité initiale ne peut pas être négative'; return null; }),
        const SizedBox(height: 18),
        TextFormField(controller: _reasonController, maxLines: 2, decoration: const InputDecoration(labelText: 'Motif / remarque (facultatif)', prefixIcon: Icon(Icons.notes))),
        const SizedBox(height: 28),
        FilledButton.icon(onPressed: _saving ? null : () => _save(products), icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check), label: Text(_saving ? 'Enregistrement…' : 'Valider le mouvement')),
      ]));
    }),
  );
}

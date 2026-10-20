import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
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
  String? _productId;
  late StockOperation _operation;
  bool _saving = false;

  @override
  void initState() { super.initState(); _operation = widget.initialOperation; }
  @override
  void dispose() { _quantityController.dispose(); _reasonController.dispose(); super.dispose(); }

  String get _title => switch (_operation) { StockOperation.entry => 'Entrée de stock', StockOperation.exit => 'Sortie de stock', StockOperation.count => 'Inventaire physique' };

  Future<void> _save(List<Product> products) async {
    if (!_formKey.currentState!.validate()) return;
    final matches = products.where((p) => p.id == _productId);
    if (matches.isEmpty) return;
    final product = matches.first;
    final value = int.parse(_quantityController.text);
    final newStock = _operation == StockOperation.entry ? product.stock + value : _operation == StockOperation.exit ? product.stock - value : value;
    if (_operation == StockOperation.exit && value > product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock insuffisant pour cette sortie.'))); return;
    }
    setState(() => _saving = true);
    final type = _operation == StockOperation.entry ? 'Entrée' : _operation == StockOperation.exit ? 'Sortie' : 'Inventaire';
    final recordedQuantity = _operation == StockOperation.count ? (value - product.stock).abs() : value;
    try {
      await HistoryService.record(productId: product.id, productName: product.name, type: type, quantity: recordedQuantity, previousStock: product.stock, newStock: newStock, reason: _reasonController.text.trim());
      if (!mounted) return;
      context.read<ProductBloc>().add(UpdateProduct(Product(id: product.id, name: product.name, barcode: product.barcode, barcode2: product.barcode2, price: product.price, stock: newStock)));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mouvement enregistré.')));
      context.pop();
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: Text(_title)), body: BlocBuilder<ProductBloc, ProductState>(builder: (context, state) {
      final products = state.products;
      final selected = products.where((p) => p.id == _productId).firstOrNull;
      return Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(20), children: [
        SegmentedButton<StockOperation>(segments: [SegmentedButtonSegment(value: StockOperation.entry, label: Text('Entrée'), icon: Icon(Icons.add)), SegmentedButtonSegment(value: StockOperation.exit, label: Text('Sortie'), icon: Icon(Icons.remove)), SegmentedButtonSegment(value: StockOperation.count, label: Text('Inventaire'), icon: Icon(Icons.fact_check))], selected: {_operation}, onSelectionChanged: (v) => setState(() { _operation = v.first; _quantityController.clear(); })),
        const SizedBox(height: 24),
        DropdownButtonFormField<String>(value: _productId, isExpanded: true, decoration: const InputDecoration(labelText: 'Produit', prefixIcon: Icon(Icons.inventory_2_outlined)), items: products.map((p) => DropdownMenuItem(value: p.id, child: Text('${p.name} • stock : ${p.stock}', overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() => _productId = v), validator: (v) => v == null ? 'Choisissez un produit' : null),
        if (selected != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Stock actuel : ${selected.stock} unité(s)', style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(height: 18),
        TextFormField(controller: _quantityController, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: InputDecoration(labelText: _operation == StockOperation.count ? 'Quantité réellement comptée' : 'Quantité', prefixIcon: const Icon(Icons.numbers)), validator: (v) { final n = int.tryParse(v ?? ''); if (n == null || n < (_operation == StockOperation.count ? 0 : 1)) return _operation == StockOperation.count ? 'Saisissez une quantité valide (0 ou plus)' : 'La quantité doit être supérieure à zéro'; return null; }),
        const SizedBox(height: 18),
        TextFormField(controller: _reasonController, maxLines: 2, decoration: const InputDecoration(labelText: 'Motif / remarque (facultatif)', prefixIcon: Icon(Icons.notes))),
        if (selected != null && int.tryParse(_quantityController.text) != null && _operation == StockOperation.count) Padding(padding: const EdgeInsets.only(top: 14), child: Text('Écart : ${int.parse(_quantityController.text) - selected.stock} unité(s)')),
        const SizedBox(height: 28),
        FilledButton.icon(onPressed: _saving || products.isEmpty ? null : () => _save(products), icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check), label: Text(_saving ? 'Enregistrement…' : 'Valider le mouvement')),
      ]));
    }));
  }
}

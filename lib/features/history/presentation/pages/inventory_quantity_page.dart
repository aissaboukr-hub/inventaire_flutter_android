import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../product/domain/entities/product.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../../data/history_service.dart';

const _green = AppTheme.primaryColor;
const _dark = AppTheme.backgroundColor;
const _panel = AppTheme.surfaceColor;

class InventoryQuantityPage extends StatefulWidget {
  final Map<String, dynamic> session;
  final Product product;
  final String type;
  const InventoryQuantityPage({super.key, required this.session, required this.product, required this.type});
  @override State<InventoryQuantityPage> createState() => _InventoryQuantityPageState();
}
class _InventoryQuantityPageState extends State<InventoryQuantityPage> {
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  bool _saving = false;
  bool get _isIn => widget.type == 'in';
  @override void dispose() { _quantity.dispose(); _reason.dispose(); super.dispose(); }
  Future<void> _save() async {
    final amount = int.tryParse(_quantity.text.trim());
    if (amount == null || amount <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saisissez une quantité supérieure à zéro.'))); return; }
    final product = widget.product;
    final delta = _isIn ? amount : -amount;
    final newStock = product.stock + delta;
    if (newStock < 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock insuffisant pour cette sortie.'))); return; }
    setState(() => _saving = true);
    try {
      final box = Hive.box('inventory_sessions');
      final data = Map<String, dynamic>.from(box.get(widget.session['id']) as Map? ?? widget.session);
      final counts = Map<String, dynamic>.from(data['products'] as Map? ?? {});
      final oldDelta = int.tryParse('${counts[product.id] ?? 0}') ?? 0;
      counts[product.id] = oldDelta + delta;
      data['products'] = counts;
      await HistoryService.record(productId: product.id, productName: product.name, type: _isIn ? 'Entrée' : 'Sortie', quantity: amount, previousStock: product.stock, newStock: newStock, reason: _reason.text.trim().isEmpty ? 'Inventaire : ${data['name']}' : _reason.text.trim());
      if (!mounted) return;
      context.read<ProductBloc>().add(UpdateProduct(Product(id: product.id, name: product.name, barcode: product.barcode, barcode2: product.barcode2, price: product.price, stock: newStock)));
      await box.put(data['id'], data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isIn ? 'Entrée enregistrée : +$amount' : 'Sortie enregistrée : -$amount')));
      context.pop();
    } finally { if (mounted) setState(() => _saving = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: _dark,
    appBar: AppBar(backgroundColor: Theme.of(context).appBarTheme.backgroundColor, foregroundColor: Theme.of(context).colorScheme.onSurface, title: Text(widget.product.name, overflow: TextOverflow.ellipsis)),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [Expanded(child: _operationCard('IN', 'Ajouter (+)', true)), const SizedBox(width: 10), Expanded(child: _operationCard('OUT', 'Retirer (−)', false))]),
      const SizedBox(height: 24),
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.product.name, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 20)), const SizedBox(height: 6), Text(widget.product.barcodeDisplay, style: const TextStyle(color: Colors.black54)), const SizedBox(height: 16), Text('Stock actuel : ${widget.product.stock}', style: const TextStyle(color: Colors.black54, fontSize: 16))])),
      const SizedBox(height: 20),
      TextField(controller: _quantity, autofocus: true, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], style: const TextStyle(color: Colors.black87, fontSize: 24, fontWeight: FontWeight.bold), decoration: InputDecoration(labelText: 'Quantité', labelStyle: const TextStyle(color: Colors.black54), filled: true, fillColor: _panel, prefixIcon: Icon(_isIn ? Icons.add : Icons.remove, color: _isIn ? AppTheme.primaryColor : Colors.redAccent), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      const SizedBox(height: 16),
      TextField(controller: _reason, maxLines: 2, style: const TextStyle(color: Colors.black87), decoration: InputDecoration(labelText: 'Motif (facultatif)', labelStyle: const TextStyle(color: Colors.black54), filled: true, fillColor: _panel, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      const SizedBox(height: 28),
      SizedBox(height: 56, child: FilledButton(onPressed: _saving ? null : _save, style: FilledButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white), child: _saving ? const CircularProgressIndicator() : const Text('SAUVEGARDER', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 16)))),
    ]),
  );
  Widget _operationCard(String label, String subtitle, bool isIn) => InkWell(onTap: () { if ((isIn && !_isIn) || (!isIn && _isIn)) context.pushReplacement('/inventory/quantity', extra: {'session': widget.session, 'product': widget.product, 'type': isIn ? 'in' : 'out'}); }, child: Container(padding: const EdgeInsets.symmetric(vertical: 18), decoration: BoxDecoration(color: (isIn == _isIn) ? _green : _panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: (isIn == _isIn) ? _green : Colors.white12)), child: Column(children: [Text(label, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 23)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: Colors.black54))])));
}

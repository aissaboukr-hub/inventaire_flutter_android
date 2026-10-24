import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../../../product/domain/entities/product.dart';

const _green = AppTheme.primaryColor;
const _dark = AppTheme.backgroundColor;

class InventoryDetailPage extends StatefulWidget {
  final Map<String, dynamic> session;
  const InventoryDetailPage({super.key, required this.session});
  @override State<InventoryDetailPage> createState() => _InventoryDetailPageState();
}
class _InventoryDetailPageState extends State<InventoryDetailPage> {
  String _query = '';
  Future<void> _updateCount(Product product, int delta) async {
    final box = Hive.box('inventory_sessions');
    final data = Map<String, dynamic>.from(box.get(widget.session['id']) as Map? ?? widget.session);
    final counts = Map<String, dynamic>.from(data['products'] as Map? ?? {});
    final old = int.tryParse('${counts[product.id] ?? 0}') ?? 0;
    counts[product.id] = old + delta;
    data['products'] = counts;
    await box.put(data['id'], data);
    setState(() => widget.session['products'] = counts);
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: _dark,
    appBar: AppBar(backgroundColor: Theme.of(context).appBarTheme.backgroundColor, foregroundColor: Theme.of(context).colorScheme.onSurface, title: Text(widget.session['name'] ?? 'Inventaire', overflow: TextOverflow.ellipsis), actions: [PopupMenuButton<String>(iconColor: Colors.black54, onSelected: (v) { if (v == 'history') context.push('/history'); }, itemBuilder: (_) => const [PopupMenuItem(value: 'history', child: Text('Historique des mouvements'))])]),
    body: BlocBuilder<ProductBloc, ProductState>(builder: (context, state) {
      final counts = Map<String, dynamic>.from(widget.session['products'] as Map? ?? {});
      final products = state.products.where((p) => counts.containsKey(p.id) && (p.name.toLowerCase().contains(_query.toLowerCase()) || p.barcodes.any((b) => b.contains(_query)))).toList();
      return Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: TextField(onChanged: (v) => setState(() => _query = v.trim()), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Rechercher un produit', filled: true, fillColor: Theme.of(context).colorScheme.surface))), const SizedBox(width: 8), IconButton.filled(onPressed: () async { final code = await context.push<String>('/scanner'); if (code != null && mounted) setState(() => _query = code.trim()); }, style: IconButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white), icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scanner un code-barres')])) ,
        Container(width: double.infinity, color: AppTheme.surfaceColor, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Text('${products.length} produit(s) saisi(s)', style: const TextStyle(color: Colors.black54))),
        Expanded(child: products.isEmpty ? const Center(child: Text('Aucun produit saisi dans cet inventaire', style: TextStyle(color: Colors.black54))) : ListView.separated(itemCount: products.length, separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.black12), itemBuilder: (context, i) {
          final p = products[i]; final adjustment = int.tryParse('${counts[p.id] ?? 0}') ?? 0;
          return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), title: Text(p.name, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 17)), subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text('${p.barcodeDisplay}\nStock : ${p.stock}', style: const TextStyle(color: Colors.black54, height: 1.4))), isThreeLine: true, trailing: SizedBox(width: 116, child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text('$adjustment', style: TextStyle(color: adjustment == 0 ? Colors.white : AppTheme.primaryColor, fontSize: 20, fontWeight: FontWeight.bold)), const Text('écart saisi', style: TextStyle(color: Colors.black54, fontSize: 11))])), onTap: () => _showActions(p, adjustment));
        })),
      ]);
    }),
    floatingActionButton: FloatingActionButton(backgroundColor: _green, foregroundColor: Colors.white, onPressed: () => context.push('/products/add'), child: const Icon(Icons.add)),
  );
  void _showActions(Product p, int adjustment) {
    showModalBottomSheet(context: context, backgroundColor: AppTheme.surfaceColor, builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.name, style: const TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 6), Text('Stock actuel : ${p.stock} • Écart saisi : $adjustment', style: const TextStyle(color: Colors.black54)), const SizedBox(height: 18), Row(children: [Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: _green), onPressed: () { Navigator.pop(ctx); context.push('/inventory/quantity', extra: {'session': widget.session, 'product': p, 'type': 'in'}); }, icon: const Icon(Icons.arrow_downward), label: const Text('IN  +'))), const SizedBox(width: 12), Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: AppTheme.backgroundColor), onPressed: () { Navigator.pop(ctx); context.push('/inventory/quantity', extra: {'session': widget.session, 'product': p, 'type': 'out'}); }, icon: const Icon(Icons.arrow_upward), label: const Text('OUT  −')))]), const SizedBox(height: 10), SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () async { await _updateCount(p, 0); if (ctx.mounted) Navigator.pop(ctx); }, icon: const Icon(Icons.fact_check), label: const Text('Marquer / consulter le comptage')))]))));
  }
}

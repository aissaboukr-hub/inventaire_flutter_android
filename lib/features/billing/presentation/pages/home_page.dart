import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../../../product/domain/entities/product.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventaire'),
        actions: [
          IconButton(tooltip: 'Historique', icon: const Icon(Icons.history), onPressed: () => context.push('/history')),
          IconButton(tooltip: 'Paramètres', icon: const Icon(Icons.settings_outlined), onPressed: () => context.push('/settings')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => context.read<ProductBloc>().add(LoadProducts()),
        child: BlocBuilder<ProductBloc, ProductState>(builder: (context, state) {
          final products = state.products;
          final totalUnits = products.fold<int>(0, (sum, p) => sum + p.stock);
          final lowStock = products.where((p) => p.stock > 0 && p.stock <= 5).length;
          final outOfStock = products.where((p) => p.stock <= 0).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(20)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Vue d’ensemble du stock', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Text('${products.length}', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold)),
                  const Text('références enregistrées', style: TextStyle(color: Colors.white)),
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(child: _metric('Unités en stock', '$totalUnits', Icons.inventory_2_outlined)),
                    Expanded(child: _metric('Stock faible', '$lowStock', Icons.warning_amber_rounded)),
                    Expanded(child: _metric('Ruptures', '$outOfStock', Icons.remove_shopping_cart_outlined)),
                  ]),
                ]),
              ),
              const SizedBox(height: 22),
              const Text('Actions rapides', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _action(context, Icons.inventory_2_outlined, 'Catalogue des produits', 'Ajouter, rechercher ou modifier les références', () => context.push('/products')),
              _action(context, Icons.add_circle_outline, 'Entrée de stock', 'Réceptionner des quantités', () => context.push('/movements?type=entry')),
              _action(context, Icons.remove_circle_outline, 'Sortie de stock', 'Enregistrer une sortie ou une perte', () => context.push('/movements?type=exit')),
              _action(context, Icons.fact_check_outlined, 'Inventaire physique', 'Compter et corriger les écarts', () => context.push('/movements?type=count')),
              _action(context, Icons.history, 'Historique des mouvements', 'Consulter toutes les opérations enregistrées', () => context.push('/history')),
              const SizedBox(height: 8),
              if (state.status == ProductStatus.loading) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
            ],
          );
        }),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, color: Colors.white, size: 19), const SizedBox(width: 6),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11))])),
  ]);

  Widget _action(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
    margin: const EdgeInsets.only(bottom: 9), child: ListTile(leading: CircleAvatar(child: Icon(icon)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: onTap));
}

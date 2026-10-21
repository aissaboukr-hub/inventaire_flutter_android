import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../product/presentation/bloc/product_bloc.dart';

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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
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

  Widget _action(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
    margin: const EdgeInsets.only(bottom: 9), child: ListTile(leading: CircleAvatar(child: Icon(icon)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: onTap));
}

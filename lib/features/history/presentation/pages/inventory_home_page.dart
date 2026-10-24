import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

const _green = Color(0xFF009B65);
const _dark = Color(0xFF111111);
const _panel = Color(0xFF202126);

class InventoryHomePage extends StatelessWidget {
  const InventoryHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('inventory_sessions');
    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text("Liste d'inventaire", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [PopupMenuButton<String>(onSelected: (v) {
          if (v == 'history') context.push('/history');
          if (v == 'settings') context.push('/settings');
          if (v == 'products') context.push('/products');
        }, itemBuilder: (_) => const [PopupMenuItem(value: 'history', child: Text('Historique')), PopupMenuItem(value: 'products', child: Text('Produits')), PopupMenuItem(value: 'settings', child: Text('Paramètres'))])],
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<dynamic> sessions, _) {
          final items = sessions.values.whereType<Map>().toList().reversed.toList();
          if (items.isEmpty) return const Center(child: Text('Aucun inventaire.\nAppuyez sur + pour en créer un.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 17)));
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white24, height: 1),
            itemBuilder: (context, index) {
              final item = Map<String, dynamic>.from(items[index]);
              final products = (item['products'] as Map?)?.length ?? 0;
              final date = DateTime.tryParse('${item['createdAt'] ?? ''}');
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                title: Text('${item['name'] ?? 'Inventaire'}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                subtitle: Padding(padding: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('⌄  Afficher les détails', style: TextStyle(color: Color(0xFF80DDB9), fontSize: 16)), const SizedBox(height: 6), Text('$products produit(s) compté(s)${date == null ? '' : ' • ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'}', style: const TextStyle(color: Colors.white60))])),
                trailing: PopupMenuButton<String>(iconColor: Colors.white70, onSelected: (v) async { if (v == 'delete') await sessions.delete(item['id']); if (v == 'rename' && context.mounted) { final c = TextEditingController(text: '${item['name']}'); final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Renommer l’inventaire'), content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Nom')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Enregistrer'))])); if (name != null && name.isNotEmpty) { item['name'] = name; await sessions.put(item['id'], item); } } }, itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Renommer')), PopupMenuItem(value: 'delete', child: Text('Supprimer'))]),
                onTap: () => context.push('/inventory/detail', extra: item),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _green, foregroundColor: Colors.white,
        onPressed: () async {
          final c = TextEditingController(text: 'Inventaire ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}');
          final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Nouvel inventaire'), content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Nom de l’inventaire')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Créer'))]));
          if (name == null || name.isEmpty || !context.mounted) return;
          final id = const Uuid().v4(); final data = <String, dynamic>{'id': id, 'name': name, 'createdAt': DateTime.now().toIso8601String(), 'products': <String, dynamic>{}};
          await box.put(id, data);
          if (context.mounted) context.push('/inventory/detail', extra: data);
        },
        icon: const Icon(Icons.add, size: 30), label: const Text('Nouvel inventaire', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

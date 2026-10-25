import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/history_service.dart';

class HistoryPage extends StatefulWidget {
  final Map<String, dynamic>? session;
  const HistoryPage({super.key, this.session});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  void initState() { super.initState(); HistoryService.init().then((_) { if (mounted) setState(() {}); }); }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final movements = HistoryService.all(inventoryId: session == null ? null : '${session['id'] ?? ''}');
    return Scaffold(
      appBar: AppBar(title: Text(session == null ? 'Historique des mouvements' : 'Historique : ${session['name'] ?? 'Inventaire'}')),
      body: movements.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.history, size: 52), SizedBox(height: 12), Text('Aucun mouvement enregistré', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)), SizedBox(height: 6), Text('Les entrées, sorties et saisies de cet inventaire apparaîtront ici.', textAlign: TextAlign.center)])))
          : ListView.separated(
              padding: const EdgeInsets.all(12), itemCount: movements.length, separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final m = movements[index];
                final type = m['type'] as String? ?? 'Mouvement';
                final qty = m['quantity'] as int? ?? 0;
                final date = DateTime.tryParse(m['date'] as String? ?? '');
                final color = type == 'Entrée' ? Colors.green : type == 'Sortie' ? Colors.red : Colors.orange;
                return ListTile(
                  leading: CircleAvatar(backgroundColor: color.withValues(alpha: .12), child: Icon(type == 'Entrée' ? Icons.south_west : type == 'Sortie' ? Icons.north_east : Icons.fact_check_outlined, color: color)),
                  title: Text(m['productName'] as String? ?? 'Produit'),
                  subtitle: Text('${type}${m['reason'] == null || (m['reason'] as String).isEmpty ? '' : ' • ${m['reason']}'}\n${date == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(date)} • Stock : ${m['previousStock']} → ${m['newStock']}'),
                  isThreeLine: true,
                  trailing: Text('${type == 'Entrée' ? '+' : type == 'Sortie' ? '-' : '±'}$qty', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
                );
              }),
    );
  }
}

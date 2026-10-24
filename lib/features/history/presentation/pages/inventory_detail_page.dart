import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../../../product/domain/entities/product.dart';

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
    counts[product.id] = old + delta;
    data['products'] = counts;
    await box.put(data['id'], data);
    if (!mounted) return;
    setState(() => widget.session['products'] = counts);
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
              onSelected: (v) {
                if (v == 'history') context.push('/history');
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'history', child: Text('Historique des mouvements')),
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
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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

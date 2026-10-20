import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/data_transfer_service.dart';
import '../../../product/presentation/bloc/product_bloc.dart';

class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});

  @override
  State<ImportExportPage> createState() => _ImportExportPageState();
}

typedef ImportAction = Future<ImportResult> Function({void Function(ImportProgress)? onProgress});

class _ImportExportPageState extends State<ImportExportPage> {
  late final TextEditingController _url;
  bool _loading = false;
  ImportProgress? _progress;
  DateTime? _lastProgressPaint;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: DataTransferService.defaultGoogleSheetsImportUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _run(ImportAction action, {required String verb}) async {
    setState(() {
      _loading = true;
      _progress = const ImportProgress(processed: 0, total: 0, imported: 0, duplicates: 0, errors: 0);
    });
    try {
      final result = await action(onProgress: (progress) {
        // Une mise à jour visuelle trop fréquente ralentit elle-même l'import.
        // On limite donc les rebuilds à ~20/s tout en gardant le dernier état.
        final now = DateTime.now();
        if (_lastProgressPaint == null || now.difference(_lastProgressPaint!) >= const Duration(milliseconds: 50) || progress.processed == progress.total) {
          _lastProgressPaint = now;
          if (mounted) setState(() => _progress = progress);
        }
      });
      if (mounted) {
        context.read<ProductBloc>().add(LoadProducts());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result.imported} produit(s) $verb • ${result.duplicates} doublon(s) • ${result.errors} erreur(s).'),
            backgroundColor: result.errors > 0 ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progress = null;
        });
      }
    }
  }

  bool get _googleLinkEmpty => _url.text.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(title: const Text('Importation / Mise à jour')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Importer la liste', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('Importer depuis Excel'),
              subtitle: const Text('Ajoute les produits du fichier à la liste existante.'),
              onTap: _loading ? null : () => _run(DataTransferService.importProductsFromExcel, verb: 'importé(s)'),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_download),
              title: const Text('Importer depuis Google Sheets'),
              subtitle: const Text('Ajoute les produits de la feuille à la liste existante.'),
              onTap: _loading || _googleLinkEmpty ? null : () => _run(({void Function(ImportProgress)? onProgress}) => DataTransferService.importProductsFromGoogleSheets(_url.text, onProgress: onProgress), verb: 'importé(s)'),
            ),
          ),
          const SizedBox(height: 28),
          const Text('Mettre à jour la liste', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Un produit est reconnu grâce à Code-barres 1 ou Code-barres 2. Son prix, son nom et ses codes sont mis à jour. Le stock actuel est conservé.'),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.table_view),
              title: const Text('Mettre à jour depuis Excel'),
              subtitle: const Text('Ajoute les nouveaux produits et actualise les produits existants.'),
              onTap: _loading ? null : () => _run(DataTransferService.updateProductsFromExcel, verb: 'mis à jour'),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Mettre à jour depuis Google Sheets'),
              subtitle: const Text('Ajoute les nouveaux produits et actualise les produits existants.'),
              onTap: _loading || _googleLinkEmpty ? null : () => _run(({void Function(ImportProgress)? onProgress}) => DataTransferService.updateProductsFromGoogleSheets(_url.text, onProgress: onProgress), verb: 'mis à jour'),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'Lien Google Sheets',
              hintText: 'https://docs.google.com/spreadsheets/d/...',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          const Text('Format obligatoire', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Excel et Google Sheets doivent contenir exactement 4 colonnes, dans cet ordre : Code-barres 1, Code-barres 2, Nom, Prix. Aucune autre colonne n’est autorisée. Code-barres 2 est facultatif.'),
          if (_loading && progress != null) ...[
            const SizedBox(height: 20),
            _buildProgress(progress),
          ],
        ],
      ),
    );
  }

  Widget _buildProgress(ImportProgress progress) {
    final total = progress.total;
    final ratio = total == 0 ? 0.0 : progress.percentage.clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Importation en cours', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: total == 0 ? null : ratio),
            const SizedBox(height: 10),
            Text(total == 0 ? 'Préparation du fichier…' : 'Lignes traitées : ${progress.processed} / $total'),
            if (total > 0) Text('Avancement : ${(ratio * 100).toStringAsFixed(1)} %'),
            const SizedBox(height: 4),
            Text('Produits importés : ${progress.imported}'),
            Text('Doublons : ${progress.duplicates}'),
            Text('Erreurs : ${progress.errors}'),
          ],
        ),
      ),
    );
  }
}

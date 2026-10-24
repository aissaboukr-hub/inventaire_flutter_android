# Modifications demandées

- Les utilisateurs non administrateurs peuvent ouvrir uniquement l'écran d'ajout de produit (`/products/add`) depuis le détail d'un inventaire. La liste complète du catalogue et l'édition restent réservées à l'administrateur.
- Suppression de l'action « Enregistrer le fichier Excel » ; seul le partage Excel reste disponible depuis le menu de l'inventaire. Le menu de partage Android permet de choisir WhatsApp, Bluetooth ou une autre application installée.
- Le nom du fichier Excel suit le format `NomInventaire_NomUtilisateur.xlsx`.
- Ajout de la colonne « Date et heure de saisie » à l'export. La date est enregistrée lors de la première saisie du produit dans l'inventaire.
- Dans le détail de l'inventaire, les produits sont triés par date/heure de première saisie, du plus ancien au plus récent.
- Compatibilité conservée avec les inventaires existants : les produits déjà présents sans date de saisie utilisent la date de création de l'inventaire comme date de repli.

## Vérification
Flutter n'est pas disponible dans l'environnement de préparation. Vérifier avec `flutter pub get`, `flutter analyze` et `flutter build apk --release`.

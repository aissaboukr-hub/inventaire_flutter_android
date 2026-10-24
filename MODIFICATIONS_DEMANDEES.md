# Modifications demandées

- Les écrans d’inventaire utilisent maintenant la palette existante de l’application (`AppTheme`) au lieu des couleurs vert foncé/noir ajoutées pour la maquette.
- Le détail d’un inventaire affiche uniquement les produits dont l’identifiant figure déjà dans les données de cet inventaire. Un produit marqué/compté à zéro reste visible, car il a bien été saisi.
- La recherche et le scan filtrent maintenant uniquement parmi les produits saisis dans cet inventaire.

Pour vérifier : `flutter pub get`, `flutter analyze`, puis `flutter build apk --release`.

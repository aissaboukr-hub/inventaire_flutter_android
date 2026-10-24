# Modification : détail d’un inventaire

- Lorsque la recherche est vide, la liste affiche uniquement les produits déjà saisis dans l’inventaire courant.
- La recherche manuelle fonctionne sur le nom et les codes-barres, y compris pour les produits pas encore saisis.
- Le bouton scanner lance la caméra puis recherche le code-barres scanné dans le catalogue.
- Les produits trouvés via la recherche ou le scan peuvent être ouverts puis saisis via IN / OUT.
- Un code-barres introuvable affiche un message dédié et ne laisse pas une ancienne notification d’erreur.
- Le bouton d’effacement rétablit la liste des seuls produits saisis.

À vérifier sur la machine de développement : `flutter pub get`, `flutter analyze`, puis `flutter build apk --release`.

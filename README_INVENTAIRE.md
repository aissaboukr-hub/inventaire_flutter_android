# Application d'inventaire Android

Cette version transforme l'écran d'accueil de l'application de caisse en tableau de bord de stock. Les écrans de caisse, de paiement et de retours ne sont plus accessibles depuis la navigation principale.

## Fonctionnalités ajoutées

- Tableau de bord : références, unités en stock, stock faible (1 à 5 unités) et ruptures.
- Entrées de stock avec motif facultatif.
- Sorties de stock avec blocage si la quantité demandée dépasse le stock disponible.
- Inventaire physique : saisie de la quantité comptée et calcul de l'écart.
- Historique local persistant des mouvements, avec date, quantité avant/après, type et motif.
- Réutilisation du catalogue produit, du scan de codes-barres et de la base Hive existants.

## Stockage et migration

Les produits restent stockés dans la boîte Hive `products`, donc les produits déjà présents sur l'appareil ne sont pas supprimés par cette modification. L'historique des mouvements est conservé dans la nouvelle boîte `stock_movements`. Les opérations effectuées avant cette version ne peuvent pas être reconstituées rétroactivement dans cet historique.

## Générer l'application Android

Avec Flutter SDK installé :

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

L'APK devrait être généré sous `build/app/outputs/flutter-apk/app-release.apk`.

## Notes

- Le projet source utilise encore le modèle de produit existant, dont le champ `price` reste requis par le modèle de données. Il n'est plus utilisé par le tableau de bord d'inventaire.
- Les données restent locales à l'appareil ; aucune synchronisation multi-appareils n'est ajoutée.
- Avant une mise en production, lancer `flutter analyze` et tester les entrées, sorties, inventaires, sauvegardes et restauration sur un appareil Android réel.

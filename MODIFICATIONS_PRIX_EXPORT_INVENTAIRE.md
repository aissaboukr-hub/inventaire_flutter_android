# Modifications : prix facultatif et export d’inventaire

- Le prix dans « Ajouter un produit » est maintenant facultatif. Un prix vide est enregistré à 0 DA et apparaît vide dans le fichier exporté. Les prix saisis doivent rester numériques et non négatifs.
- Dans le détail d’un inventaire, le menu en haut à droite propose « Partager Excel (WhatsApp / Bluetooth) » et « Enregistrer le fichier Excel ».
- Le fichier exporté contient uniquement les produits déjà saisis dans cet inventaire : nom, deux codes-barres, stock actuel, écart saisi et prix.
- Le partage ouvre la feuille de partage Android ; WhatsApp ou Bluetooth sont disponibles selon les applications installées et les capacités de l’appareil.

Vérification locale recommandée : `flutter pub get`, `flutter analyze`, puis `flutter build apk --release`. La compilation n’a pas été exécutée dans l’environnement de préparation.

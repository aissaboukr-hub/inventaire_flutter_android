# Correction du nom du fichier Excel partagé

Le partage utilisait `XFile.fromData`, ce qui peut faire apparaître un nom temporaire UUID sur Android (par exemple `fcb-11f1-9b15-517513967fbc.xlsx`).

Le partage écrit maintenant le classeur dans un vrai fichier temporaire dont le nom est construit par `_exportFileName()`, puis partage ce chemin de fichier.

Format attendu : `NomInventaire_NomUtilisateur.xlsx`

Vérifier sur l'appareil en ouvrant le partage WhatsApp ou Bluetooth. Exécuter `flutter pub get`, `flutter analyze` et `flutter build apk --release` avant installation.

# Améliorations de l'inventaire physique

Cette archive conserve la structure et les fonctionnalités du projet fourni.

## Correction incluse
- L'historique conserve désormais le signe de la quantité pour les corrections d'inventaire physique (ex. `-2`), au lieu d'enregistrer uniquement sa valeur absolue.
- Le message de scan précédent est fermé avant l'affichage du résultat du scan suivant, afin d'éviter les notifications obsolètes.

## Fonctionnement existant conservé
- Scan ou saisie du code-barres.
- Correction positive/négative du stock lors de l'inventaire physique.
- Ajout d'un produit inconnu pendant l'inventaire avec code-barres, nom et prix.
- Vérification empêchant un stock final négatif.
- Entrées, sorties, historique, import/export et fonctions existantes du projet.

## Vérification
Le code a été modifié dans la source, mais Flutter n'est pas disponible dans l'environnement de préparation.
Exécuter localement depuis le dossier du projet :
`flutter pub get`
`flutter analyze`
`flutter build apk --release`

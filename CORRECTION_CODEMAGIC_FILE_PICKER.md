Correction de la compilation Android Codemagic

- Mise à niveau de file_picker vers 12.0.0, qui utilise une implémentation Android séparée compatible avec AGP 9.
- Adaptation des deux imports Excel à la nouvelle valeur de retour de FilePicker.pickFiles() (List<PlatformFile>).
- Mise à niveau du SDK Dart minimum à 3.10, requis par file_picker 12.
- Alignement du wrapper Gradle sur 9.5.0, de l’Android Gradle Plugin sur 9.3.1 et de Kotlin Gradle Plugin sur 2.4.20, conformément aux avertissements Flutter du journal fourni.
- Suppression de local.properties (chemin Flutter local à une machine) et du GeneratedPluginRegistrant.java généré, qui sera recréé par flutter pub get.

Codemagic doit exécuter flutter pub get avant la compilation pour régénérer pubspec.lock et l’enregistrement des plugins.

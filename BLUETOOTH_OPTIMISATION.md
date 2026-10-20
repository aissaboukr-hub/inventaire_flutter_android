# Bluetooth — correction

La logique de connexion a été simplifiée conformément à la demande :

- aucune limite de tentatives ;
- aucun timeout ajouté par l'application ;
- un seul appel direct à `PrintBluetoothThermal.connect()` ;
- aucune nouvelle tentative artificielle après échec ;
- l'adresse de l'imprimante enregistrée est utilisée directement ;
- aucune recherche complète des appareils lorsqu'une imprimante connue est disponible ;
- une connexion déjà établie est conservée pendant la session ;
- le verrouillage des connexions simultanées est conservé pour éviter deux appels concurrents.

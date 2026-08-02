# avatars/rive/ — exports Rive & test de chargement

Dossier des fichiers `.riv` de la Phase 0 (cf. `docs/RIVE_PHASE0_BRIEF.md`).

## Où déposer l'export

Exporte depuis Rive et pose le fichier ici sous le nom :

```
avatars/rive/combattant_profil.riv
```

## Tester qu'il se charge

Ouvre **`test-loader.html`** (double-clic, ou via une page servie en local) :

1. clique **« Charger ./combattant_profil.riv »** (ou glisse un `.riv` dans le champ fichier) ;
2. le journal doit afficher ✅ et lister les **artboards**, **state machines** et **anims** ;
3. vérifie les deux coches attendues : `✓ artboard 'combattant_profil'` et `✓ state machine 'combat'` ;
4. choisis la state machine `combat`, clique **Afficher** : le combattant s'anime ;
5. les **inputs** de la machine apparaissent en boutons (dont le trigger **`impact`** réservé pour les FX) — clique pour les déclencher.

> La page de test charge le runtime Rive depuis le CDN (open source, MIT) → elle a
> besoin d'une connexion. C'est une page de **dev**, séparée du jeu ; `index.html`
> n'embarque rien tant que le `.riv` n'est pas validé.

## Critère de gel du squelette

Voir la checklist §7 de `docs/RIVE_PHASE0_BRIEF.md`. Le test décisif : un cosmétique
posé sur un os (ex. kabuto sur `head`) suit l'anim **sans avoir été ré-animé**.

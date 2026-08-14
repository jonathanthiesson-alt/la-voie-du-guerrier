# Skins de combattant — sprites

**Où déposer les fichiers** : un dossier par skin, directement ici.

```
images/skins/
  <skin>/                     ← nom en minuscules, sans espace ni accent
    01_attack_haut.png
    02_pare_haut.png
    03_attack_milieu.png
    04_pare_milieu.png
    05_attack_bas.png
    06_pare_bas.png
    07_esquive_haut.png
    08_esquive_milieu.png
    09_esquive_bas.png
    10_salut.png
    11_blesse_adversaire.png
    12_touche.png
    13_garde_posture.png      ← LA pose de référence (preview du carrousel)
    nouveau_salut_formel.png
    pose_blesse_par_terre.png
  skins_manifest.json         ← généré, NE PAS éditer à la main
```

C'est exactement l'arborescence de `all_sprites.zip` : on peut **dézipper
directement ici**, sans rien renommer.

## Règles

- **15 poses par skin, toujours les mêmes noms.** Un skin incomplet est ignoré
  par le manifeste (mieux vaut un skin absent qu'un skin qui affiche du vide en
  plein combat).
- **281 × 256 px**, fond transparent. Toute autre dimension casse l'alignement
  des deux combattants dans le bandeau.
- Le nom du dossier est l'**identifiant technique** — il part en base dans le
  profil du joueur, donc **il ne change jamais** une fois livré. Le nom affiché
  (« Aztèque », « Mousquetaire ») vit dans le manifeste, lui modifiable.

## Régénérer le manifeste

Après tout ajout / retrait de skin :

```bash
node scripts/build-skins-manifest.mjs
```

Le manifeste liste les skins complets et leur libellé FR. Les libellés déjà
présents sont **conservés** : le script ne réécrit que la liste, il n'écrase pas
la traduction d'un skin existant.

## Poids

~108 Ko par PNG, 15 poses → **~1,6 Mo par skin**. À 36 skins on dépasse 57 Mo :
c'est pour ça que le jeu ne charge JAMAIS tout (voir le chargement paresseux
côté client — seule la pose `13_garde_posture` alimente le carrousel).
La conversion WebP du lot est suivie dans la tâche « pipeline d'assets ».

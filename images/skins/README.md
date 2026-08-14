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

## WebP (généré)

`node scripts/convert-skins-webp.mjs` (nécessite `npm install`, dépendance
`sharp` en devDependency uniquement — absente du runtime jeu) génère un
`.webp` à côté de chaque `.png`, qualité 85 : **57,2 Mo → 6,1 Mo** sur les 540
sprites actuels. Les PNG restent en place (source de vérité, pas de perte).
À relancer après tout ajout/retrait de sprite.

## Contrat de chargement paresseux (client)

Le jeu ne doit JAMAIS charger les 36 skins d'un coup :

- **Carrousel de sélection** (Passe 9) : seule la pose `13_garde_posture.webp`
  de chaque skin complet (`skins_manifest.json`) est chargée — 36 images, pas
  540.
- **Popup skin sélectionné** (aperçu détaillé) : charge les 15 `.webp` du
  **seul** skin cliqué, à la demande (à l'ouverture du popup, pas avant).
- **En combat** : charge uniquement les 15 `.webp` des 2 skins réellement en
  jeu (le sien + celui de l'adversaire), une fois la partie trouvée — jamais
  au chargement de l'app.
- **Fallback** : si `.webp` absent (script pas encore lancé) ou navigateur
  sans support WebP, retomber sur le `.png` du même nom.

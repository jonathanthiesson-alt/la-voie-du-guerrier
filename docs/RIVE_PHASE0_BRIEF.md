# Brief de production — Phase 0 Rive (squelette de base)

> **Pour : Thomas (DA) + Wurmz (intégration).** Statut : prêt à exécuter
> (Rive installé, 2026-08-01). Objectif de la Phase 0 : produire **un seul
> squelette de base réel dans Rive**, gelé, sur lequel tous les cosmétiques et
> toutes les anims viendront se greffer. **C'est le seul vrai engagement lourd**
> du sous-projet — une fois ce squelette figé, le reste (skins, anims) est de
> l'ajout léger.
>
> Cadre : cf. `docs/AVATARS_SKINS.md` (la spec) et `docs/ANIMATIONS_CATALOGUE.md`
> (les 19 gestes). Rappel : **un seul combattant** habillé, pas une armée.

---

## 0. La règle d'or (à ne jamais casser)

**Un squelette unique, gelé tôt, partagé par TOUT.** Mêmes os pour toutes les
anims et tous les cosmétiques. C'est ce qui permet de vendre une anim seule
(fatality, salut) sur laquelle les skins déjà équipés se greffent automatiquement :

- **Anim = pur mouvement d'os** (aucun dessin dedans).
- **Cosmétique = dessin accroché à un os** (aucun mouvement dedans).

Si on ajoute/retire/renomme un os plus tard, **toutes** les anims et **tous** les
skins déjà faits cassent. Donc Phase 0 = poser les bons os **une fois**.

---

## 1. Périmètre Phase 0 (ce qu'on fait / ce qu'on ne fait PAS)

| On FAIT | On ne fait PAS (plus tard) |
|---|---|
| 1 squelette de base complet (corps + visage) | Les vues arrière / OTS (Phase 1) |
| **Vue de profil ¾ uniquement** (le plan « Plateau ») | Les FX manga (lignes de vitesse, flash, shake…) |
| 1 skin de test « nu » (silhouette grise) pour valider le rig | Les vrais cosmétiques peints |
| 3–4 anims de validation (idle, salut, réflexion yeux, une frappe) | Les 19 clips complets |
| 1 state machine minimale + 1 trigger `impact` | La logique de jeu |

**Pourquoi profil seul :** en 2.5D une vue de dos = **un autre dessin**, pas une
rotation. On ne double pas le coût tant que le squelette de profil n'est pas
validé. L'OTS (Pokémon) et le gros plan yeux viendront en Phase 1 comme
artboards/skins séparés sur le **même** squelette.

---

## 2. Le squelette — os exacts (repris du proto)

Ces os viennent de `avatars/proto.html` (moteur placeholder déjà validé dans le
navigateur). **Reproduire ces noms et cette hiérarchie à l'identique** dans Rive :
c'est ce qui garantit que le `.riv` sera compatible avec l'intégration prévue.

Repère : origine `root` aux hanches, **Y vers le haut = négatif** (comme en SVG).
Coordonnées = position de l'os **par rapport à son parent**, taille ≈ **170 unités
du sol au sommet du crâne** (≈ 7,5 têtes, proportions humaines réelles).

| Os | Parent | x | y | Rôle |
|---|---|---:|---:|---|
| `root` | — | 0 | 0 | bassin / pivot global |
| `spine` | root | 0 | −4 | bas du dos |
| `chest` | spine | 0 | −58 | torse (porte le plastron) |
| `neck` | chest | 0 | −90 | cou |
| `head` | neck | 0 | −98 | tête (porte casque + visage) |
| `shoulderR` | chest | 18 | −84 | épaule droite (bras du sabre) |
| `elbowR` | shoulderR | 24 | −48 | coude droit |
| `handR` | elbowR | 30 | −14 | main droite |
| `osArme` | handR | 30 | −14 | **os de l'arme** (le sabre s'y accroche) |
| `shoulderL` | chest | −20 | −82 | épaule gauche (bras du bouclier) |
| `elbowL` | shoulderL | −26 | −48 | coude gauche |
| `handL` | elbowL | −26 | −16 | main gauche |
| `osBouclier` | handL | −26 | −16 | **os du bouclier/garde** |
| `hipR` | root | 10 | −2 | hanche droite |
| `kneeR` | hipR | 14 | 60 | genou droit |
| `footR` | kneeR | 12 | 122 | pied droit |
| `hipL` | root | −10 | −2 | hanche gauche |
| `kneeL` | hipL | −16 | 60 | genou gauche |
| `footL` | kneeL | −14 | 122 | pied gauche |

### 2b. Le visage EST dans le squelette (crucial)

La réal manga (yeux qui se plissent en réflexion, sourcil qui se fronce) impose
des **os de visage dès le jour 1**, enfants de `head`. À poser dans Rive :

| Os visage | Parent | Rôle |
|---|---|---|
| `browR` / `browL` | head | sourcils (froncement) |
| `lidTopR` / `lidTopL` | head | paupières hautes (plissement, clignement) |
| `eyeR` / `eyeL` | head | globe / direction du regard |
| `jaw` | head | mâchoire (cri, effort) |

> Sans ces os, **aucune anim d'expression ne se greffera** : casques et masques
> sont des slots posés **par-dessus** ces os, ils ne les remplacent pas.

---

## 3. Slots cosmétiques → os d'ancrage

Chaque cosmétique est un dessin **parenté à l'os indiqué** (il suit l'os,
c'est tout). Slots repris du proto :

| Slot | S'accroche à l'os | Exemples |
|---|---|---|
| `casque` | `head` | Kabuto, Kabuto à cornes, Menpō (masque) |
| `plastron` | `chest` | Dō plaque, Dō lamellaire |
| `epaules` | `shoulderR` **+** `shoulderL` | Sode (une pièce par épaule) |
| `tassettes` | `root` (bassin) | Kusazuri |
| `jambes` | `kneeR` **+** `kneeL` | Suneate |
| `sabre` | `osArme` | lame (longueur/courbe variables) |
| `garde` | `osBouclier` | tsuba / petit bouclier |

Le **corps nu** (peau/kimono de base) est aussi un skin, parenté aux os du tronc
et des membres — c'est le skin de test de la Phase 0.

---

## 4. Procédure Rive (pas à pas)

1. **Nouveau fichier** → 1 artboard nommé `combattant_profil`, format ~720×470
   (même ratio que la scène du proto).
2. **Dessiner le corps de test** en pièces séparées (tête, torse, bras haut/bas,
   mains, cuisses, mollets, pieds) — silhouette grise suffit. Vue **profil ¾**.
3. **Bones tool** → poser les os **dans l'ordre et aux positions du §2** (parent
   d'abord). Respecter les noms **à la lettre** (`osArme`, `osBouclier`, etc.).
4. **Poser les os de visage** (§2b) comme enfants de `head`.
5. **Bind (mesh)** : accrocher chaque morceau de dessin à son os (skinning Rive).
6. **Vérifier le bind** en bougeant chaque os : rien ne doit se déchirer.
7. **State Machine** `combat` minimale :
   - états `idle` ↔ `reflexion` ↔ `strike`,
   - un **Trigger `impact`** (le hook FX pour plus tard — on le pose vide
     maintenant, il ne coûte rien ; cf. `docs/FX_MANGA_BRIEF.md` §5),
   - inputs booléens/triggers nommés simplement (`toReflexion`, `toStrike`).
8. **3–4 anims de validation** (timeline courte chacune) :
   - `idle` : respiration + clignement, appuis marqués (poids sur les jambes),
   - `salut` (rei) : inclinaison, yeux fermés,
   - `reflexion` : gros plan implicite — paupières qui se plissent, sourcil froncé,
   - `strike` : une frappe de sabre ample avec fente avant (appui).
9. **Export `.riv`** → le déposer dans `avatars/rive/combattant_profil.riv`.

---

## 5. Conventions de nommage (non négociables)

- **Os** : exactement ceux du §2/§2b, casse comprise (`shoulderR`, pas `Shoulder_R`).
- **Artboard** : `combattant_profil` (Phase 1 ajoutera `combattant_ots`,
  `combattant_face` — mêmes os).
- **Anims** : minuscules, sans espace, alignées sur les clés moteur du catalogue
  (`idle`, `salut`, `reflexion`, `strike`… cf. `ANIMATIONS_CATALOGUE.md` §5).
- **State machine** : `combat`. **Trigger FX** : `impact`.
- **Skins Rive** (Phase 1) : un skin = un slot d'un cosmétique (`casque_kabuto`,
  `sabre_long`…), toujours sur le même squelette.

---

## 6. Comment le `.riv` se branche dans le jeu (pour Wurmz, plus tard)

- Runtime **Rive Web** (canvas WASM), lib open source embarquée dans `index.html`.
- Point d'accroche **unique et déjà existant** : `triggerCombatAnim(key, moverColor)`
  (le bandeau de combat). Aujourd'hui il affiche une image statique ; demain il
  déclenchera l'input de state machine correspondant sur l'instance Rive du
  bandeau (`#combat-anim-stage`).
- Les **8 clés moteur** (`sword-vs-sword-push`, `player-dodge`, …) mappent 1:1 sur
  des inputs/anims de la state machine `combat` (table dans `ANIMATIONS_CATALOGUE.md` §5).
- Le **placeholder `window.ProtoBanner`** (moteur 2.5D maison, gaté `_protoBannerOn`)
  reste en place jusqu'à ce que le `.riv` soit prêt : on remplace le moteur, pas
  le câblage. Zéro changement côté jeu normal.

---

## 7. Critère de validation Phase 0 (« c'est bon, on gèle »)

- [ ] Les 19 os corps + os visage sont posés aux positions du §2/§2b.
- [ ] Le skin de test bouge proprement sur les 4 anims (rien ne se déchire).
- [ ] `reflexion` montre bien un plissement d'yeux lisible (test manga).
- [ ] La state machine `combat` bascule idle/reflexion/strike + trigger `impact`.
- [ ] Un cosmétique de test (ex. un kabuto gris sur `head`) suit la tête pendant
      `strike` **sans** avoir été ré-animé (preuve de la règle d'or).
- [ ] Export `.riv` chargé dans un test navigateur sans erreur.

Une fois ces cases cochées : **le squelette est gelé.** À partir de là, ajouter un
skin = dessiner une pièce + l'accrocher à son os. Ajouter une anim = bouger des os.
Plus jamais toucher aux os eux-mêmes.

---

*Rédigé le 2026-08-01. Os repris de `avatars/proto.html` (BONES/SLOTS validés
navigateur). Phase 1 (OTS, gros plan yeux, vues arrière) et FX manga = documents
séparés à venir.*

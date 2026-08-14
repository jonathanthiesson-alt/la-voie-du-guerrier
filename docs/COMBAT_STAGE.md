# Scène de combat — décors, caméra et mise en scène des sprites

> **Rien n'est codé.** Ce document fige le vocabulaire, les dimensions et les
> propositions de mise en scène, pour qu'on tranche AVANT d'écrire une ligne.
> Il remplacera à terme la barre de tendance noir/blanc plein bandeau
> (`#win-prob-bar`) par une vraie scène façon Castlevania / Mortal Kombat.

---

## 1. L'existant (ce qu'on remplace)

| Élément | Aujourd'hui |
|---|---|
| `#combat-banner` | hauteur `clamp(110px, 20vh, 190px)`, largeur 100 % |
| `#win-prob-bar` | **fond** du bandeau : zone claire / zone sombre séparées d'un trait doré |
| `computeWinProbability()` | renvoie **0.03 → 0.97** (logistique sur `evalForWhite`, échelle ±600) |
| `updateWinProbBar()` | pose la largeur de `#win-prob-bg-white` en % |
| `#combat-anim-stage` | l'anim du coup, en grand, par-dessus (`max-height:96%`) |
| `images/combat-anims/` | **8 anims** par couleur, images composites (les deux combattants déjà dessinés dedans) |

**Le point clé** : `computeWinProbability()` existe déjà et donne exactement le
signal dont la caméra a besoin. Rien à recalculer — on rebranche.

---

## 2. Les assets

### Sprites de combattant
`images/skins/<skin>/<pose>.png` — **36 skins × 15 poses, 281 × 256 px**.

| # | Fichier | Usage en scène |
|---|---|---|
| 13 | `13_garde_posture` | **pose de repos** — l'état par défaut, et la preview du carrousel de skins |
| 01/03/05 | `attack_haut/milieu/bas` | l'attaquant |
| 02/04/06 | `pare_haut/milieu/bas` | le défenseur qui pare |
| 07/08/09 | `esquive_haut/milieu/bas` | le défenseur qui esquive |
| 10 | `salut` | début de manche |
| — | `nouveau_salut_formel` | début de **partie** (plus solennel) |
| 11 | `blesse_adversaire` | le vainqueur d'un échange |
| 12 | `touche` | le perdant d'un échange |
| — | `pose_blesse_par_terre` | **fin de partie**, le vaincu au sol |

> ⚠️ **Il n'y a AUCUNE frame de marche.** Un « pas en avant » ne peut donc pas
> être un cycle de marche : ce sera un **déplacement du sprite** (translation +
> léger rebond), pas une animation de jambes. À décider : ça suffit, ou il faut
> demander 2 frames de pas à Thomas.

### Décor de scène
`images/stages/<stage>/` — **2160 × 512 px**, pixel art à l'échelle des sprites.

- **Zone sûre horizontale** : le contenu qui doit toujours rester lisible tient
  dans les **1080 px centraux**. Le reste est de la **réserve de travelling**.
- **Zone sûre verticale** : à définir avec Thomas (cf. §3) — sur un téléphone
  court, on ne verra pas les 512 px.
- Premier décor livré : **dojo** (celui généré le 2026-08-13).

---

## 3. L'échelle — le calcul qui commande tout

Décor et sprites sont dessinés au **même pas de pixel**. Il faut donc **un seul
facteur d'échelle S**, appliqué aux deux :

```
S = hauteur_bandeau_CSS / 512
largeur_décor_à_l_écran = 2160 × S
taille_sprite_à_l_écran = 281×S  par  256×S
course_de_caméra        = 2160×S − largeur_écran
```

| Hauteur bandeau | S | Sprite affiché | Décor affiché | Course caméra (écran 400 px) |
|---|---|---|---|---|
| 190 px *(max actuel)* | 0,37 | 103 × 94 px | 800 px | **400 px** |
| 224 px | 0,44 | 123 × 112 px | 945 px | 545 px |
| **256 px** | **0,50** | **140 × 128 px** | **1080 px** | **680 px** |
| 307 px | 0,60 | 169 × 154 px | 1296 px | 896 px |

**Conclusion** : à la hauteur actuelle (190 px) les combattants font ~94 px de
haut — un peu petits pour qu'on lise leurs poses. **Il faut arbitrer la hauteur
du bandeau contre la place du plateau** (tâche L2, qui élargit justement le
plateau). Deux façons de gagner de la hauteur sans écraser le plateau :

- **A. Bandeau plus haut sur les grands écrans** : `clamp(150px, 30vh, 300px)`.
- **B. Recadrage vertical** : on n'affiche pas les 512 px, on **rogne le haut**
  (ciel / charpente) et on garde la bande d'action. Ça permet un S plus grand à
  hauteur d'écran égale. **Demande à Thomas** : que la ligne de sol et la
  hauteur des combattants tiennent dans une bande verticale connue, pour qu'on
  puisse rogner sans casser la composition.

---

## 4. Les couches (façon Mortal Kombat 3)

Aujourd'hui le décor est **un seul PNG plat**. La profondeur demande un export
en couches. Trois niveaux d'ambition :

| Niveau | Couches | Effet | Coût asset |
|---|---|---|---|
| **N1** *(faisable tout de suite)* | 1 — le PNG actuel | travelling simple, tout glisse d'un bloc | ✅ rien à faire |
| **N2** | 2 — décor / sol | le sol défile **plus vite** que le décor → sensation de profondeur | Thomas : découper la bande de sol |
| **N3** | 3 — ciel+lointain / dojo / sol | vrai parallaxe (0,3 × / 1 × / 1,4 ×) | Thomas : 3 PNG alignés |

**Recommandation** : livrer **N1**, valider le ressenti, et ne demander N2/N3
que si le travelling paraît plat. Chaque couche coûte un aller-retour avec
Thomas et 2 Mo d'assets.

---

## 5. Propositions de mise en scène

Numérotées pour qu'on puisse dire « on prend P1, P4, P8, P11 ».

### Caméra

- **P1 — Travelling piloté par la tendance.**
  `offsetX = (prob − 0.5) × 2 × course/2`. Les Blancs prennent l'avantage → la
  caméra glisse vers le territoire des Noirs : visuellement, **on avance chez
  l'adversaire**. C'est la lecture la plus intuitive (on gagne du terrain).
  Transition lente (`.8s ease-out`) pour que ça respire au lieu de sauter.
- **P1-bis — Lecture inverse** : la caméra suit *le camp en difficulté* (on le
  voit acculé au bord de la scène). Plus dramatique, moins immédiat à lire.
  **À trancher : P1 ou P1-bis.**
- **P2 — Recentrage à l'égalité.** Sous ±5 % d'écart, la caméra revient
  doucement au centre : les positions équilibrées sont visuellement calmes.
- **P3 — Secousse.** Sur une capture, courte secousse de caméra (3-4 px, 150 ms).
  Le sel de Mortal Kombat, quasi gratuit à coder.

### Combattants

- **P4 — L'écart raconte le match.** La distance entre les deux sprites suit la
  tendance : le camp qui mène **avance**, l'autre **recule**. Écart au repos
  ~60 % de la largeur visible, resserré jusqu'à ~35 % quand un camp domine.
- **P5 — Respiration.** En attente, `13_garde_posture` avec un léger va-et-vient
  vertical (±2 px, 2 s) — sans quoi la scène paraît morte entre deux coups.
- **P6 — Le pas.** Faute de frames de marche : translation + petit rebond
  (`translateY` bref) qui simule l'appui. **Ou** demander 2 frames à Thomas.
- **P7 — Posture selon la tendance.** Quand un camp est nettement mené, il passe
  en pose `pare_milieu` (sur la défensive) ; le dominant reste en garde haute.
  N'utilise que des poses **déjà livrées**.

### Les coups

- **P8 — Rejouer le coup avec les deux sprites.** Aujourd'hui `images/combat-anims/`
  contient des images **composites** (les deux personnages déjà dessinés). Avec
  les skins, il faut **recomposer** : attaquant en `attack_*`, défenseur en
  `pare_*` / `esquive_*` / `touche`. C'est ce qui rend le choix de skin visible
  en combat — sinon les skins ne servent qu'au profil.
- **P9 — Sortie de manche.** Le perdant joue `12_touche` puis
  `pose_blesse_par_terre` ; le vainqueur `11_blesse_adversaire`.
- **P10 — Le salut.** `nouveau_salut_formel` à l'ouverture de la **partie**,
  `10_salut` à chaque **manche** (Arène / Sumo en BO3). Rituel samouraï gratuit,
  gros gain d'âme.

### Habillage

- **P11 — Où passe la jauge de tendance ?** Le fond noir/blanc disparaît sous le
  décor. Proposition : un **filet fin (4-6 px) en haut ou en bas du bandeau**,
  même code couleur, même trait doré. On garde l'information sans reprendre
  toute la surface. *(Alternative : plus de barre du tout, la caméra EST
  l'indicateur — plus élégant mais moins précis.)*
- **P12 — Un décor par mode.** `dojo` par défaut · `dohyo` pour le Sumo ·
  une arène de tournoi · le champ de bataille pour le 3v3. Catalogue
  `images/stages/`, sélection par mode, même contrat 2160 × 512.
- **P13 — Décor lié au skin adverse ?** *(idée à écarter sauf coup de cœur :
  multiplie les combinaisons pour un gain faible.)*

---

## 6. Le lot minimal qui donne déjà tout

Si on veut un premier jet convaincant sans attendre d'assets supplémentaires :

**N1 + P1 + P2 + P4 + P5 + P10 + P11.**

Rien à demander à Thomas : un seul PNG de décor, les 15 poses déjà livrées, et
le signal de tendance qui existe déjà. P8 (recomposition des coups) est le gros
morceau et mérite son propre lot.

---

## 7. Décisions prises (2026-08-13, Jonathan)

### D1 — La caméra est un **réglage joueur**, pas un choix de designer
Trois modes, dans les paramètres :

| Mode | Comportement |
|---|---|
| `dominant` | la caméra suit le camp qui mène — *on gagne du terrain* |
| `dominé` | la caméra suit le camp en difficulté — *on le voit acculé* |
| `moi` | la caméra reste sur **mon** combattant du début à la fin |

Le mode `moi` est le seul qui ne dépend pas de la tendance : il fixe la caméra
sur la couleur du joueur local (et sur les Blancs en spectateur / hotseat).
Réglage persisté dans `userPrefs`, clé i18n à ajouter (fr/en/ja).

### D2 — La scène occupe **le bandeau actuel**, le filet passe **dessous**
Pas de bandeau plus haut, pas de recadrage : la scène prend exactement la
surface qu'occupait la barre noir/blanc (`clamp(110px, 20vh, 190px)`), et le
filet de tendance vient **juste en dessous**, en plus.

Conséquence chiffrée — **S = hauteur_bandeau / 512** :

| Écran | Bandeau | S | Sprite affiché |
|---|---|---|---|
| grand | 190 px | 0,37 | 104 × 95 px |
| court | 110 px | 0,21 | 60 × 55 px |

> **Réserve** : sur écran court les combattants tombent à 55 px de haut. Si à
> l'usage ça ne se lit pas, le seul levier qui ne coûte pas de hauteur d'écran
> est le **recadrage vertical** (montrer la bande d'action, pas le ciel). On ne
> le fait pas maintenant — on regarde d'abord le rendu réel.

### D3 — Pas de frames de marche
On s'en passe. Les combattants **glissent** : translation horizontale douce,
sans cycle de jambes. Rien à demander à Thomas. *(= P6, variante translation.)*

### D4 — Zone sûre verticale
Réglée par D2 : la scène entière est visible (fit height), donc pas de bande
sûre à garantir tant qu'on ne recadre pas.

### D5 — Le filet de tendance est conservé
Barre fine sous la scène, même code couleur noir/blanc et même trait doré
qu'aujourd'hui. *(= P11, variante « filet conservé ».)*

---

## 8. Les anims de coup — repartir de l'existant

Les 8 anims composites de `images/combat-anims/` sont **la référence de mise en
scène** : elles disent déjà quel geste va avec quelle situation de jeu
(poussée, capture, esquive, fatalité). On ne repart pas de zéro — on les
**analyse pose par pose** pour en déduire, pour chacune, la paire
`attaquant / défenseur` à recomposer avec les sprites de skin.

Autorisé pour tester : **générer une composition automatique** à partir des
poses individuelles et la comparer côte à côte avec l'anim composite d'origine,
pour valider que le rendu tient avant de faire les 8.

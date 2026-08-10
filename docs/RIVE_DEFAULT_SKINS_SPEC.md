# Spec — Skins par défaut (Blanc & Noir) dans Rive

> **Pour : Thomas / Wurmz.** Objectif : construire dans Rive les **deux skins par
> défaut** (le combattant de base de chaque camp) pour **tester le process complet**
> export `.riv` → jeu. Ces skins n'ont **aucune armure ajoutée** (casque, dō, sode
> viendront plus tard comme cosmétiques déblocables) : c'est le guerrier en **kimono
> + hakama**, sabre au poing.
>
> Prérequis : le **squelette gelé** de `docs/RIVE_PHASE0_BRIEF.md` (mêmes os, mêmes
> noms). Les formes ci-dessous sont reprises du proto (`avatars/proto.html`,
> `buildBase`) → les skins Rive ressembleront aux placeholders déjà validés.

---

## 0. Règle du test : DEUX skins, UN squelette

Blanc et Noir partagent **exactement le même squelette et la même state machine**.
La seule différence, ce sont **les couleurs** (et la teinte du sabre). C'est
précisément ce qu'on veut prouver : *un squelette → plusieurs skins*.

**Structure Rive recommandée pour ce test :**
- **1 fichier** `default-skins.riv`.
- **2 artboards** : `combattant_blanc` et `combattant_noir`.
- Les deux ont **les mêmes noms d'os** (cf. brief Phase 0) et **la même state
  machine `combat`** (mêmes inputs : `toReflexion`, `toStrike`, trigger `impact`).
- Le plus simple : construis **Blanc** en entier, **duplique l'artboard**, puis ne
  change que les **couleurs** pour obtenir **Noir**. Zéro reprise de rig.

> Alternative « avancée » (facultative) : un seul artboard + **data binding** de
> couleurs pour basculer Blanc/Noir. À éviter pour ce **premier** test — deux
> artboards, c'est garanti de marcher côté runtime.

---

## 1. Palettes (les 2 seules choses qui changent)

| Rôle | Clé | **Blanc** | **Noir** |
|---|---|---|---|
| Kimono (clair) | `gi` | `#e6e0d1` | `#363b45` |
| Kimono (foncé, dos) | `giDk` | `#cfc7b4` | `#272c34` |
| Peau | `skin` | `#f0d9bf` | `#e6c6a4` |
| Encre / contours | `ink` | `#2b2620` | `#0c0d10` |
| Cheveux | `hair` | `#241f19` | `#101217` |
| Col | `collar` | `#f6f2e9` | `#c7ccd6` |
| Obi (ceinture) | `obi` | `#8f3b2f` | `#2f4d8f` |
| Nœud d'obi | `lace` | `#c34a34` | `#3f6bcf` |
| **Lame du sabre** | `saber` | `#e5432f` (rouge) | `#3f7be6` (bleu) |
| Reflet de lame | `saberHi` | `#ffd9cf` | `#cfe0ff` |

*(Repère : `x` vers la droite, `y` vers le haut = négatif ; origine `root` au
bassin. Coords en unités canoniques du squelette.)*

---

## 2. Les pièces à dessiner, os par os

Chaque pièce est **parentée à l'os indiqué** (elle suit l'os). Dessine-la en pose
de repos (identité). Ordre d'empilement : de l'arrière (jambes, bras gauche) vers
l'avant (torse, tête, bras droit + sabre).

### Jambes (hakama ample, 2 segments = articulé)
| Pièce | Os | Forme (canonique) | Remplissage |
|---|---|---|---|
| Cuisse droite | `hipR` | trapèze large 10,-2 → 14,60 (largeur 19→21) | `gi`, contour `ink` |
| Mollet droit | `kneeR` | trapèze 14,60 → 12,122 (21→14) | `gi`, contour `ink` |
| Sandale droite (waraji) | `footR` | semelle plate ~ x 0..26, y 120..127 | `ink` |
| Cuisse gauche | `hipL` | trapèze -10,-2 → -16,60 (18→20) | `giDk`, contour `ink` |
| Mollet gauche | `kneeL` | trapèze -16,60 → -14,122 (20→13) | `giDk`, contour `ink` |
| Sandale gauche | `footL` | semelle plate ~ x -28..-2, y 120..127 | `#17181c` (Blanc) / `ink` (Noir) |

### Bras arrière gauche (manche de kimono)
| Pièce | Os | Forme | Remplissage |
|---|---|---|---|
| Bras haut G | `shoulderL` | trapèze -20,-82 → -26,-48 (19→12) | `giDk`, contour `ink` |
| Avant-bras G | `elbowL` | trapèze -26,-48 → -26,-16 (12→8) | `giDk`, contour `ink` |
| Main G | `handL` | cercle r≈5.5 en (-26,-16) | `skin`, contour `ink` |

### Bassin & torse
| Pièce | Os | Forme | Remplissage |
|---|---|---|---|
| Bassin | `root` | rectangle arrondi ~30×16 centré (0,0) | `giDk` |
| Kimono (torse) | `spine` | polygone épaules→taille : (-21,-84)(21,-84)(15,-40)(11,-2)(-11,-2)(-15,-40) | `gi`, contour `ink` |
| Col en V | `spine` | triangle (-13,-82)(0,-44)(13,-82) | `collar`, contour `ink` |
| Pli central | `spine` | ligne 0,-44 → 0,-78 | trait `giDk` |
| Obi (ceinture) | `spine` | rectangle x-16..16, y-36..-22 | `obi`, contour `ink` |
| Nœud d'obi | `spine` | petit rectangle x-5..4, y-36..-22 | `lace` |

### Cou, tête & visage (⚠️ le visage est DANS le squelette)
| Pièce | Os | Forme | Remplissage |
|---|---|---|---|
| Cou | `neck` | trapèze court 0,-94 → 0,-82 (11→12) | `skin`, contour `ink` |
| Cheveux | `head` | calotte ~ x -19..21, y -133..-108 | `hair` |
| Chonmage | `head` | petit rectangle sommet (~ -3..7, -141..-133) | `hair` |
| Visage | `head` | cercle r≈16 en (1,-112) | `skin`, contour `ink` |
| Œil G / Œil D | `eyeL`/`eyeR` | ellipse blanche rx≈3.4 ry≈3.2 en (4,-115) et (11,-115) + pupille r≈1.9 | blanc + `ink` |
| Sourcil G / D | `browL`/`browR` | petit trait au-dessus de chaque œil (y≈-121) | `ink` |
| Bouche | `jaw` | trait court 2,-104 → 9,-104 | `ink` |

> Les yeux/sourcils/bouche sont accrochés à **leurs os de visage** (`eyeL/R`,
> `browL/R`, `jaw`) → c'est ce qui permettra les micro-anims (plissement en
> réflexion). Ne les colle pas au `head` seul.

### Bras avant droit (porte le sabre) — dessiné en DERNIER (au-dessus)
| Pièce | Os | Forme | Remplissage |
|---|---|---|---|
| Bras haut D | `shoulderR` | trapèze 18,-84 → 24,-48 (20→12) | `gi`, contour `ink` |
| Avant-bras D | `elbowR` | trapèze 24,-48 → 30,-14 (12→8) | `gi`, contour `ink` |
| Main D | `handR` | cercle r≈6 en (30,-14) | `skin`, contour `ink` |

### Sabre (katana) — parenté à `osArme`
| Pièce | Os | Forme | Remplissage |
|---|---|---|---|
| Lame | `osArme` | lame légèrement courbe, de la main vers l'avant-haut, longueur ~50 | `saber`, reflet `saberHi` |
| Tsuba (garde) | `osArme` | petit disque à la base de la lame | `ink` |
| Tsuka (poignée) | `osArme` | petit manche court sous la tsuba | `ink` |

**C'est la lame qui porte la couleur de camp** (rouge Blanc / bleu Noir) — le
seul élément « signature » du skin par défaut. Garde la **pointe** de la lame
identifiable (repère pour la future traînée de FX, cf. `FX_MANGA_BRIEF.md` §5).

---

## 3. State machine (identique aux 2 artboards)

Reprends la state machine `combat` du brief Phase 0 :
- états `idle` ↔ `reflexion` ↔ `strike`,
- inputs : `toReflexion` (bool/trigger), `toStrike` (trigger), **`impact`** (trigger, posé vide),
- au moins les anims `idle`, `reflexion`, `strike` (+ `salut` si tu veux tester le rei).

**Même nommage dans les deux artboards** — le runtime pilotera les inputs sans
savoir quel camp est affiché.

---

## 4. Export & test

1. Export → **`avatars/rive/default-skins.riv`**.
2. Ouvre **`avatars/rive/skins-test.html`** (le harnais) : bouton **Blanc / Noir**
   (choisit l'artboard), boutons d'état (`idle`/`reflexion`/`strike`) et le
   trigger `impact`.
3. Vérifie :
   - [ ] Blanc et Noir s'affichent, **mêmes poses**, couleurs différentes, sabre rouge/bleu.
   - [ ] Basculer Blanc↔Noir ne casse rien (mêmes os, même SM).
   - [ ] `reflexion` plisse les yeux ; `strike` porte un coup ; `impact` se déclenche.
4. On regarde ça ensemble et on branche au bandeau de combat.

---

## 5. Checklist « skins par défaut prêts »

- [ ] 2 artboards `combattant_blanc` / `combattant_noir`, os identiques.
- [ ] Palettes du §1 appliquées (seules les couleurs diffèrent).
- [ ] Sabre rouge (Blanc) / bleu (Noir).
- [ ] Visage riggé sur `eyeL/R`, `browL/R`, `jaw`.
- [ ] State machine `combat` identique + trigger `impact`.
- [ ] Export `default-skins.riv` chargé dans `skins-test.html` sans erreur.

*Rédigé le 2026-08-02. Formes reprises de `avatars/proto.html` (buildBase/PAL).
Ce sont les skins **par défaut** ; les armures sont des slots cosmétiques à venir.*

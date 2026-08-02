# Catalogue d'animations — Avatars de combat

> **Statut : conception + placeholders jouables (2026-07-28).** Ce document liste
> **toutes les animations** du combattant, reliées aux **mouvements des pièces**.
> C'est la référence contre laquelle Thomas anime, et la liste des clips préfaits
> déjà prototypés dans l'éditeur (`avatars/proto.html`, onglet *Mouvement*).
>
> Rappel du cadre (cf. `docs/AVATARS_SKINS.md`) : le jeu oppose **deux
> combattants**, pas deux armées. L'**Épéiste** = le combattant ; les **Pions
> Épée** = les mouvements de son sabre ; le **Bouclier** = ses parades. Une anim =
> du **pur mouvement d'os** (aucun art dedans) → elle porte n'importe quel skin
> équipé. Tout se joue sur **1 case**, donc le catalogue est **fini** (~19 gestes).
>
> Ces clips alimentent le **mini-film du bandeau de combat** : à chaque coup joué,
> le camp qui joue exécute le clip correspondant, dressé de ses cosmétiques.

---

## 1. Cérémonie & états (hors déplacement)

| Clip | Détail | Signature vendable ? |
|---|---|---|
| **Salut d'ouverture** (rei) | les deux combattants s'inclinent l'un vers l'autre (yeux fermés) | ✅ |
| **Idle / respiration** | boucle de repos : micro-mouvements + clignements | |
| **Réflexion** (manga) | gros plan : les yeux se **plissent**, le sourcil se fronce | ✅ |
| **Victoire / défaite** | le vainqueur lève sa lame ; l'adversaire s'effondre | ✅ |

## 2. Déplacements simples (1 acteur, avance d'1 case sur du vide)

L'adversaire reste au repos. Les directions se font en **retournant le rig**
(pas un clip par direction).

| Clip | Pièce | Geste | Directions |
|---|---|---|---|
| **Pas — Épéiste** | Épéiste | le corps avance d'une case | 8 dir. |
| **Pas — Pion Épée** | Pion Épée | un coup de sabre porté vers l'avant | 4 dir. |
| **Pas — Bouclier** | Bouclier | garde levée en se déplaçant | 4 dir. |

## 3. Poussées — **8 clips** (allié coopératif ≠ ennemi combatif)

C'est le point clé : **pousser sa propre pièce** (coopératif, geste doux, solo —
on repositionne une facette de soi) **≠ pousser une pièce ennemie** (combatif,
l'adversaire encaisse et recule d'une case).

### 3a. Coopératives — cible **alliée** (adversaire au repos)
| # | Clip | Pousseur → Cible | Note |
|---|---|---|---|
| 1 | **Épéiste pousse Pion allié** | Épéiste → Pion Épée | « pousse-toi, frère » |
| 2 | **Épéiste pousse Bouclier allié** | Épéiste → Bouclier | réaligne sa garde |
| 3 | **Pion pousse Pion allié** | Pion Épée → Pion Épée | prépare la push-capture |
| 4 | **Bouclier pousse Pion allié** | Bouclier → Pion Épée | replace une frappe alliée |

### 3b. Combatives — cible **ennemie** (adversaire recule)
| # | Clip | Pousseur → Cible | Note |
|---|---|---|---|
| 5 | **Épéiste pousse Épéiste ennemi** | Épéiste → Épéiste | bousculade — déloge, jamais de capture |
| 6 | **Pion pousse Pion ennemi** | Pion Épée → Pion Épée | choc de sabres |
| 7 | **Bouclier pousse Pion ennemi** | Bouclier → Pion Épée | coup de bouclier |
| 8 | **Bouclier pousse Épéiste ennemi** | Bouclier → Épéiste | coup de bouclier qui déloge |

*Rappel des règles (d'où l'absence des autres combinaisons) : l'Épéiste ne pousse
que ses alliés Épée/Bouclier et l'Épéiste ennemi ; un Bouclier n'est jamais poussé
sauf par son propre Épéiste ; un Pion Épée ne pousse jamais un Bouclier.*

## 4. Fatalités (conditions de victoire — l'adversaire s'effondre)

| Clip | Ce qui se passe | Signature vendable ? |
|---|---|---|
| **Capture directe** | un Pion Épée arrive sur l'Épéiste adverse → frappe fatale | ✅ |
| **Push-capture** | un Pion Épée *poussé* sur l'Épéiste adverse porte le coup | ✅ |
| **Éjection** *(extension)* | poussée hors plateau — modes **Sumo / custom du Labo** uniquement | |

---

## 5. Correspondance avec le moteur du jeu

Le jeu classe chaque coup réel via `classifyCombatAnim()` en **8 clés**, qui
pilotent le bandeau. État actuel du câblage :

| Clé moteur (code) | Mouvement | Clip du catalogue |
|---|---|---|
| `sword-captures-combattant-fatality` | Pion capture Épéiste | Capture directe |
| `player-loses-slash` | Push-capture | Push-capture |
| `sword-vs-sword-push` | Pion pousse Pion **ennemi** | Pion pousse Pion ennemi (§3b #6) |
| `shield-vs-sword-push` | Bouclier pousse Pion **ennemi** | Bouclier pousse Pion ennemi (#7) |
| `shield-vs-player-push` | Bouclier pousse Épéiste **ennemi** | Bouclier pousse Épéiste ennemi (#8) |
| `player-vs-player-push` | Épéiste pousse Épéiste **ennemi** | Épéiste pousse Épéiste ennemi (#5) |
| `coop-epeiste-sword` | Épéiste pousse Pion **allié** | Épéiste pousse Pion allié (§3a #1) |
| `coop-epeiste-shield` | Épéiste pousse Bouclier **allié** | Épéiste pousse Bouclier allié (#2) |
| `coop-sword-sword` | Pion pousse Pion **allié** | Pion pousse Pion allié (#3) |
| `coop-shield-sword` | Bouclier pousse Pion **allié** | Bouclier pousse Pion allié (#4) |
| `sword-attack-miss` | Pion se déplace | Pas — Pion Épée |
| `player-dodge` | Épéiste se déplace | Pas — Épéiste |
| `shield-parry` | Bouclier se déplace | Pas — Bouclier *(classé mais sans image en jeu normal)* |

### ✅ Écart allié/ennemi COMBLÉ (2026-08-01)
`classifyCombatAnim(moverType, targetType, mv, targetIsAlly)` reçoit désormais un
**drapeau allié/ennemi**, calculé à chaque point d'appel (coup local, IA, en
ligne, analyse) en comparant la **couleur de la pièce cible** à celle du joueur
qui bouge. Les poussées coopératives renvoient les 4 clés `coop-*` ci-dessus.
En **jeu normal** elles n'ont pas encore d'image → le bandeau **reste silencieux**
(conforme à l'intention historique : ne pas afficher un choc combatif pour un
geste coopératif). En **mode proto (dev)**, le `ProtoBanner` joue pour ces clés un
**geste doux** (le pousseur avance, l'adversaire **reste au repos**), là où les
poussées combatives déclenchent **frappe + recul de l'adversaire**.

### ⚠️ Écart restant
- **Pas de clé « pas du Pion »** distincte du déplacement à vide générique — à
  ajouter si on veut différencier les trois déplacements en jeu.

---

## 6. Plans / caméras (mise en scène)

En 2.5D ce sont des **plans montés**, pas une caméra 3D libre (cf.
`docs/AVATARS_SKINS.md` §4). Catalogue des cadrages :

| Plan | Cadrage | Usage |
|---|---|---|
| **Plateau** | vue de profil, les deux combattants côte à côte | défaut hors mise en scène |
| **Combat « OTS »** (façon Pokémon) | **par-dessus l'épaule** : le combattant **du joueur** de **dos / ¾ arrière** au premier plan, l'adversaire en face | plan d'immersion du duel |
| **Fatality** | rapproché, dramatique | coup fatal |
| **Salut** | les deux face à face | ouverture |
| **Gros plan yeux** | serré sur le visage / les yeux | réflexion du joueur, parades |

> **🔴 Règle de POV — chaque joueur voit depuis SON combattant.** Les plans
> immersifs (OTS, gros plans) sont cadrés du **point de vue du combattant du
> joueur qui regarde** (le Blanc voit son guerrier de dos et le Noir en face ;
> inverse pour le Noir). Même partie, **rendu par joueur**.

> **⚠️ Coût 2.5D.** Une vue de **dos / ¾ arrière** = **un autre dessin** (pas une
> rotation), sur le même squelette → chaque cosmétique visible en OTS a besoin de
> sa **silhouette arrière**. À trancher : OTS = cadrage **par défaut** (coûteux)
> ou **ponctuel** (dramatique). En Rive : un **artboard/skin par plan**.

*Tous les mouvements ci-dessus sont **prototypés** (placeholders dessinés dans le
code) dans `avatars/proto.html` → sélecteurs **Plan** (Plateau / Combat OTS / Gros
plan yeux) et **Mouvement**, + bouton **Acteur/POV** (Blanc/Noir). Les vues OTS et
gros plan sont des **maquettes de cadrage** (les vraies vues arrière/face viennent
de Rive + l'art de Thomas). Rédigé le 2026-07-28, plans ajoutés le 2026-07-29.*

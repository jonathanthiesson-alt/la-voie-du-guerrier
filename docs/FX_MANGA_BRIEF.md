# Brief — FX manga (couche de mise en scène)

> **Pour : Wurmz (intégration) + Thomas (DA).** Statut : **conception, à faire
> après la Phase 0 Rive** (cf. `docs/RIVE_PHASE0_BRIEF.md`). Tranché avec Wurmz le
> 2026-08-01 : **les FX viennent plus tard**, ils sont **non contraignants** pour
> la Phase 0 — à condition de réserver **deux points d'accroche gratuits** dès
> maintenant (voir §5). Ce doc décrit ce qu'on ajoutera, pas ce qu'on code tout de
> suite.
>
> Cadre : les avatars alimentent le **mini-film du bandeau de combat** (cf.
> `docs/AVATARS_SKINS.md`, `docs/ANIMATIONS_CATALOGUE.md`). Les FX sont ce qui fait
> passer un clip d'os « correct » à une image qui **claque comme un manga**.

---

## 1. Principe : les FX sont une COUCHE, pas des os

🔑 **Les FX ne touchent pas le squelette gelé.** Un effet manga n'est jamais du
mouvement d'os : c'est une **surcouche de compositing** posée **par-dessus** le
combattant déjà dessiné et animé. D'où : on peut geler le rig en Phase 0 sans
connaître un seul FX, et les ajouter ensuite sans rien casser (règle d'or
préservée).

Trois raisons de les séparer :
- **Indépendance** : un FX se règle/ajoute/retire sans réanimer un clip.
- **Réutilisation** : le même « flash d'impact » sert à toutes les fatalités.
- **Style** : c'est ici que vit la « vraie réal manga », pas dans les articulations.

---

## 2. Catalogue des FX (par famille)

| FX | Ce que c'est | Déclenché par | Portée |
|---|---|---|---|
| **Lignes de vitesse** (集中線) | traits radiaux ou horizontaux qui convergent | frappes, fentes, fatalités | plein bandeau |
| **Flash d'impact** | éclair blanc bref au point de contact | trigger `impact` | local (point) |
| **Screen shake** | secousse courte de tout le cadre | impacts lourds, fatalités | bandeau entier |
| **Zoom / punch-in** | rapprochement sec puis relâche | fatalité, parade décisive | caméra (cadrage) |
| **Traînée de lame** (残像) | rémanence colorée qui suit la pointe du sabre | tout coup de sabre | suit `osArme` |
| **Onomatopée** (ドン, ズバッ) | gros kana d'impact posé sur le cadre | impacts, fatalités | overlay typographique |
| **Vignette / assombrissement** | bords sombres pour concentrer l'œil | gros plans, réflexion | bandeau entier |
| **Éclat de couleur** (camp) | halo rouge (Blanc) / bleu (Noir) sur le coup | frappe portée | autour du combattant |

> Ces FX **se composent** : une fatalité = zoom + screen shake + flash + lignes de
> vitesse + onomatopée, empilés. C'est l'empilement qui fait le « moment manga ».

---

## 3. Où chaque FX vit techniquement

Le bandeau de combat est un empilement de plans (du fond vers l'avant) :

```
┌─ bandeau de combat ────────────────────────────┐
│  [4] Overlay FX plein cadre : lignes de vitesse,│  ← SVG/canvas au-dessus
│      vignette, onomatopées, flash plein écran   │
│  [3] Combattants Rive (.riv, os + skins)        │  ← l'anim
│  [2] Décor / fond de plan                       │
│  [1] Jauge de tendance de victoire              │  ← existant, inchangé
└─────────────────────────────────────────────────┘
   + [0] Transforms sur le conteneur : screen shake, zoom (CSS transform)
```

- **Screen shake / zoom** = `transform` CSS animé sur le **conteneur** du bandeau
  (ne touche ni le rig ni les FX internes). Le moins cher, le plus spectaculaire.
- **Traînée de lame** = soit un FX Rive attaché à l'os `osArme` (rémanence dans le
  `.riv`), soit un overlay qui lit la position de la pointe. Réserver le bout de
  lame en Phase 0 (§5).
- **Flash / lignes de vitesse / onomatopées / vignette** = **overlay** au-dessus
  du canvas Rive (SVG inline ou 2ᵉ canvas), déclenché par le trigger `impact`.

---

## 4. Correspondance FX ↔ clés de coup

On réutilise les **clés moteur** existantes (cf. `ANIMATIONS_CATALOGUE.md` §5) pour
décider quels FX empiler. Proposition de départ :

| Clé de coup | FX empilés |
|---|---|
| `sword-captures-combattant-fatality` | zoom + shake fort + flash + lignes convergentes + onomatopée + vignette |
| `player-loses-slash` (push-capture) | shake + flash + lignes + éclat de camp |
| `*-push` **combatif** (ennemi recule) | shake léger + éclat de camp + traînée de lame |
| `coop-*` **coopératif** (allié) | **aucun / discret** (geste doux → pas de baston visuelle) |
| `sword-attack-miss` / `player-dodge` / `shield-parry` | traînée de lame légère, pas d'impact |
| `reflexion` (gros plan yeux) | vignette + léger zoom, **pas** de lignes de combat |

> Cohérent avec le gap allié/ennemi comblé : les poussées **coopératives** ne
> déclenchent **pas** de FX de combat (ce serait contradictoire).

---

## 5. 🔴 Les deux seuls points d'accroche à réserver en Phase 0

Pour que « les FX plus tard » reste **non contraignant**, il suffit de poser
**maintenant**, gratuitement, dans le `.riv` (déjà prévu dans le brief Rive) :

1. **Un os de pointe de lame** (`osArme` porte déjà la lame ; garder la **pointe**
   accessible — un bone enfant ou un marqueur en bout de lame) → point d'ancrage de
   la **traînée de lame** et du **flash au contact**.
2. **Le trigger `impact`** dans la state machine `combat` (déjà au brief Rive,
   posé **vide**) → le signal qui, plus tard, déclenchera l'overlay FX au bon
   frame, sans réanimer le clip.

Rien d'autre n'est requis côté Phase 0. Tout le reste des FX est de la surcouche
d'intégration ajoutée après coup.

---

## 6. Ordre de mise en œuvre (quand on y viendra)

Du plus rentable (effort faible / impact fort) au plus fin :

1. **Screen shake + zoom** (CSS transform sur le conteneur) — quasi gratuit, énorme effet.
2. **Flash d'impact** sur `impact` (overlay blanc bref).
3. **Lignes de vitesse** (SVG procédural : N traits convergents, opacité pulsée).
4. **Éclat de couleur de camp** (halo rouge/bleu réutilisant la palette existante).
5. **Traînée de lame** (rémanence sur la pointe).
6. **Onomatopées / vignette** (typo + dégradé de bords) — finition.

Chaque étape est **indépendante et incrémentale** : on peut s'arrêter à 2 et déjà
« sentir le manga ».

---

## 7. Garde-fous

- **Lisibilité d'abord** : les FX ne doivent jamais masquer qui gagne/perd. La
  jauge de tendance [1] reste toujours lisible.
- **Accessibilité** : prévoir un cran « FX réduits » (respecter
  `prefers-reduced-motion` pour le shake/zoom).
- **Perf** : le bandeau tourne pendant la partie → overlays légers (SVG/CSS, pas
  de shaders lourds), FX bornés dans le temps (0,2–0,6 s), jamais de boucle FX
  permanente.
- **Cosmétiques** : à terme, un **pack de FX** peut devenir un cosmétique vendable
  (« traînée de lame dorée », « onomatopées signature ») — même logique
  d'économie que les skins. À garder en tête, pas à coder maintenant.

---

*Rédigé le 2026-08-01. Décision Wurmz : FX après Phase 0, non contraignants,
réserver os de pointe + trigger `impact`. Ce doc est la référence quand on
attaquera la couche FX.*

# Avatars de combat & cosmétiques — spec du sous-projet

> **Statut : conception (2026-07-28).** Sous-projet « à part » du jeu principal :
> un système d'**avatars de combat modulaires et personnalisables**, avec un
> outil pour créer skins + animations à partir de l'artwork 2D de Thomas.
> Ce document est la **référence contre laquelle Thomas dessine** et contre
> laquelle on code. Rien n'est encore implémenté.

---

## 1. La vision en une phrase

Le jeu oppose **deux combattants** (pas deux armées). Chaque camp = **un seul
guerrier**, éclaté sur le plateau en pièces qui sont ses facettes :
- **Épéiste = le combattant lui-même** (corps, armure, kimono, casque) ;
- **Pions Épée = les mouvements de son sabre** (ses frappes matérialisées) ;
- **Bouclier = ses mouvements défensifs** (parades, contres).

On **habille donc un guerrier**, pas une troupe : son sabre équipé définit
l'apparence de ses Pions Épée, sa garde son Bouclier, son corps son Épéiste — la
cohérence est **automatique** puisque c'est une seule personne. L'apparence est
**assemblée au moment du combat** à partir de cosmétiques que le joueur
**débloque / gagne / achète** (casques, armures, kimonos, sabres, auras…), et
tout bouge grâce à un catalogue fini d'animations (déplacements, poussées,
fatalities, salut d'ouverture).

## 2. Le carrefour, tranché

| Décision | Choix | Pourquoi |
|---|---|---|
| **Fidélité / rigs** | **2.5D squelettique** (l'art de Thomas découpé et monté sur un squelette 2D) | Un nouveau cosmétique = **un dessin accroché à un os**. En vrai 3D, chaque cosmétique = une maille modélisée + riggée + weight-paintée → irréaliste pour produire *des dizaines* de skins à deux. |
| **Outil** | **Rive** en tête, **Spine** en alternative | Tous deux ont le concept natif de *skins/attachments* (= slots de cosmétiques) et un **runtime web JS**. Rive : éditeur accessible, runtime léger gratuit à petite échelle, machines à états. Spine : référence du métier, sa fonction « skins » est faite *exactement* pour ça, mais payant. DragonBones = repli gratuit. |
| **Granularité** | **Hybride** : set complet (un look qui remplit tous les slots) **ou** slots individuels — sur **un combattant unique** | Cohérence garantie (c'est une seule personne) **et** expression fine slot par slot. |
| **Cible du rendu** | ⏸️ *À décider plus tard* — mais l'assemblage est **forcément runtime** | On ne peut PAS pré-cuire les combinaisons (des milliers). Au minimum, la tenue est composée en direct par slots ; ça penche vers un runtime live (Rive web) plutôt qu'un pré-rendu total. |
| **🔑 Règle d'or** | **Un squelette unique, gelé tôt** — mêmes os pour TOUTES les anims et TOUS les cosmétiques | C'est ce qui permet de **vendre une animation seule** (fatality/salut) sur laquelle les skins déjà possédés **se greffent tout seuls** : une anim = mouvement d'os (zéro art dedans), un cosmétique = art accroché aux os. Casser le squelette = casser la greffe. |

> **Pourquoi pas le vrai 3D ?** La caméra libre serait un plus, mais elle ne
> justifie pas de transformer Thomas en modeleur 3D ni de re-sculpter chaque
> cosmétique en volume. Le 2.5D préserve sa patte au pixel près et **passe à
> l'échelle** côté production de cosmétiques. La piste 3D/Blender reste notée
> pour d'éventuels visuels marketing pré-rendus (hors gameplay).

## 3. On a déjà l'embryon : WurmzSkin

`WurmzSkin` **remplace déjà toute l'armurerie d'un camp** par des PNG
(`BLANC-BOUCLIER.png`, `BLANC-EPEE_GAUCHE.png`, `BLANC-EPEE_DROITE.png`, idem
`NOIR-*`). C'est **une skin d'armée complète** chargée depuis des images. Le
système de cosmétiques est la **généralisation par-slots** de ce qui existe déjà
pour un seul skin. Point d'entrée code : `WURMZ_SKIN_BASE` (~l. 6183).

Notez : les épées ont une variante **gauche/droite** (`EPEE_GAUCHE`/`EPEE_DROITE`)
— l'**orientation compte**. Un rig 2.5D qu'on retourne/oriente règle ça
proprement (plus besoin d'un asset par direction).

---

## 4. Rig spec (le squelette commun)

Un **squelette humanoïde 2.5D unique**, partagé par les trois pièces (elles n'en
diffèrent que par la pose de repos et l'équipement par défaut). Vue de plateau :
**3/4 légèrement plongeante** (à confirmer au proto).

### Os (hiérarchie)
```
root (bassin)
├─ spine → chest → neck → head
│                          └─ visage : paupière.G/D · sourcil.G/D · mâchoire
├─ épaule.G → bras.G → avant-bras.G → main.G
├─ épaule.D → bras.D → avant-bras.D → main.D
├─ cuisse.G → tibia.G → pied.G
├─ cuisse.D → tibia.D → pied.D
├─ os-arme        (parenté à main.D — porte la lame)
├─ os-bouclier    (parenté à main.G — porte le tate)
└─ os-bannière    (parenté à spine — sashimono / mon)
```
Os de déformation optionnels pour le tissu (jupe de kimono, manches) si l'outil
le permet (Rive/Spine gèrent le maillage déformable).

> **🔴 Décision squelette gelé (2026-07-28) — le visage est DANS le squelette de
> base.** Les os de paupières / sourcils / mâchoire sont figés dès le jour 1,
> avec le reste. Raison : on veut des **micro-anims façon réal manga** (les yeux
> qui se plissent quand l'adversaire réfléchit, un sourcil qui se lève) — c'est
> le point fort du maillage déformable de Rive, piloté par machine à états. Si le
> visage n'est pas dans le squelette gelé, **aucune anim d'expression ne se
> greffera** sur les skins existants (règle d'or, §2). **Les casques/masques sont
> des slots posés PAR-DESSUS** ce visage (et peuvent en masquer une partie). Le
> catalogue d'anims gagne donc, plus tard, des **clips d'expression** (réflexion,
> tension, sourire) qui restent des cosmétiques signature.

> **Le squelette est agnostique au style.** Le style graphique vit **dans le
> dessin de Thomas**, pas dans les os : un même squelette porte aussi bien un
> samouraï peint réaliste qu'un skin **plat façon *Samurai Jack*** (Tartakovsky).
> Les styles à aplats sont même **plus faciles** (moins de dégradés qui cassent à
> la déformation) et **plusieurs styles coexistent** comme skins concurrents — un
> argument de vente, pas une contrainte.

### Emplacements (« slots ») = points d'accroche des cosmétiques
Chaque slot est une **couche d'art** liée à un os. C'est l'unité de
personnalisation.

| Groupe | Slot | Contenu (ex.) | Os d'accroche | S'affiche sur |
|---|---|---|---|---|
| **Silhouette** | 🥋 Tenue de base | armure segmentée · kimono · tenue cyber | corps | le combattant (Épéiste) |
| **Armure** ¹ | 🪖 Casque / masque | kabuto + menpō, visière | head | le combattant |
| **Armure** ¹ | 💪 Épaules & bras | sode + kote | épaules / avant-bras | le combattant |
| **Armure** ¹ | 🩻 Plastron (dō) | plaque de torse | chest | le combattant |
| **Armure** ¹ | ⛓ Tassettes (kusazuri) | plaques de hanches | bassin | le combattant |
| **Armure** ¹ | 🦵 Jambes | haidate (cuisses) + suneate (tibias) | cuisses / tibias | le combattant |
| **Arme / défense** | 🗡 Sabre | katana · wakizashi · lame-énergie | os-arme | ses **Pions Épée** (+ lame de l'Épéiste) |
| **Arme / défense** | 🛡 Garde / bouclier | motif du tate, style de parade | os-bouclier | son **Bouclier** |
| **Identité / FX** | 🎌 Emblème d'école (ryū) + palette | mon personnel, teinte | os-bannière + teinte | tout le guerrier |
| **Identité / FX** | ✨ Aura / VFX | traînée de lame, particules cyber | root (écran) | tout le guerrier |
| **Animations** | 🙇 Signature | *salut* · *fatality* (clips échangeables) | (clip d'anim) | tout le guerrier |

¹ *Ces slots **décomposent** la « tenue de base » quand elle est de type armure
segmentée. Vendus en **set complet aujourd'hui**, **à la pièce plus tard** — même
système de slots, **zéro refactor**. Un kimono / une tenue cyber occupe la
silhouette d'un seul tenant (pas de plaques séparées).*

Le slot **Signature** est spécial : ce n'est pas de l'art posé, c'est un **clip
d'animation échangeable** (une fatality ou un salut « signature » acheté/gagné).
On peut donc **vendre une animation seule** en boutique : comme une anim n'est
que du **mouvement d'os** (aucun art dedans), les **cosmétiques déjà équipés du
joueur se greffent dessus automatiquement** dès qu'il la choisit dans ses
paramètres d'animation. Le runtime choisit le clip par joueur — natif dans les
machines à états de Rive/Spine.
⚠️ Vrai **uniquement** si le squelette est gelé (§2, règle d'or) : une anim
vendue plus tard doit viser les mêmes os. **Nuance** : une fatality chorégraphiée
pour un katana peut mal rendre sur un sabre à silhouette exotique → soit on
contraint les silhouettes de sabre, soit on autorise un **override d'anim** par
cosmétique extrême.

### Caméras / points de vue canoniques
> **🔴 Décision (2026-07-28) — « points de vue » = des PLANS montés, pas une
> caméra 3D libre.** La « réal manga » voulue (gros plan sur les yeux,
> contre-plongée sur la fatality, cadrage diagonal) s'obtient par des **cadrages
> d'auteur**, montés une fois — exactement comme un jeu 2D façon anime fait ses
> cinématiques. Ce qu'on n'a **pas**, c'est une caméra qu'on oriente librement en
> temps réel autour de la scène (ça, c'est la 3D, écartée §2). Chaque plan coûte
> un peu de montage. Une **fatality signature** vendue en boutique peut embarquer
> **son propre cadrage** → argument de vente.

Plans canoniques (en 2.5D = angles mis en scène + parallaxe) :
1. **Plateau** — l'angle par défaut, comment la pièce se tient sur sa case.
2. **Combat « OTS » (façon combat Pokémon)** — vue **par-dessus l'épaule** : le
   combattant **du joueur** au premier plan, vu de **dos / trois-quarts arrière**,
   l'adversaire en face qui le regarde. C'est le plan d'immersion du duel.
3. **Fatality** — cadrage rapproché et dramatique pour le coup fatal.
4. **Salut** — les deux combattants face à face, ouverture du combat.
5. **Gros plan / réflexion & parade** — cadrage serré sur le visage / les yeux
   (réflexion du joueur, parade), support des micro-anims des yeux.

> **🔴 Règle de POV (2026-07-29) — chaque joueur voit depuis SON combattant.**
> Les plans immersifs (OTS, gros plans) sont cadrés du **point de vue du
> combattant du joueur qui regarde** : le Blanc voit **son** guerrier de dos et le
> Noir en face ; le Noir voit l'inverse. Même partie, **rendu par joueur** (comme
> le loadout estampillé par couleur, §6).
>
> **⚠️ Conséquence 2.5D à budgéter.** Une vue de **dos / ¾ arrière** n'est PAS une
> rotation du rig de profil — c'est **un autre dessin** (le combattant vu de
> derrière) sur le même squelette. Donc chaque cosmétique qui apparaît dans le
> plan OTS doit exister aussi en **silhouette arrière**. **À trancher** : l'OTS
> est-il le **cadrage par défaut du combat** (coûteux — vue arrière pour tous les
> cosmétiques) ou un **plan ponctuel** (dramatique, vues arrière limitées) ?
> En Rive, chaque plan = un **artboard/skin dédié** (le back n'est jamais gratuit).

---

## 5. Catalogue d'animations (fini et composable)

Trois pièces × deux camps, **tout se joue sur 1 case**. La **couleur** ne change
que le skin (rig retourné), **mais pousser un allié ≠ pousser un ennemi** : le
premier est un geste **coopératif** (« pousse-toi, frère »), le second est
**combatif** (bousculade, coup de bouclier). Chaque poussée dont la cible peut
être alliée *ou* ennemie compte donc **double**. On parle d'**une vingtaine de
gestes** (~22), le reste se génère en orientant le rig.

### 🎌 Cérémonie & états
| Anim | Détail | Signature ? |
|---|---|---|
| Salut d'ouverture (rei) | les deux Épéistes s'inclinent (1 animé, miroir) | ✅ cosmétique |
| Idle / respiration | 1 boucle par pièce → **3** | |
| Sélection | la pièce se soulève/s'illumine | |
| Pose de victoire / défaite | Épéiste vainqueur ; Épéiste qui tombe → **2** | |

### 🥾 Déplacements simples (1 acteur)
| Anim | Directions |
|---|---|
| Épéiste — le pas | 8 dir. (rotation du rig, pas 8 clips) |
| Pion Épée — le pas | 4 dir. (rotation) |
| Bouclier — le pas | 4 dir. (rotation) |

### 🤜 Poussées (2 acteurs : pousseur avance d'1, poussé recule d'1) — **8 clips**
**Cible alliée et cible ennemie = deux animations distinctes** (coopératif vs
combatif). D'après la table des règles « qui pousse quoi » :
| # | Pousseur → Cible | Ton |
|---|---|---|
| 1 | Épéiste → Pion Épée **allié** | coopératif |
| 2 | Épéiste → Bouclier **allié** | coopératif |
| 3 | Épéiste → Épéiste **ennemi** | combat — déloge, jamais de capture |
| 4 | Pion Épée → Pion Épée **allié** | coopératif (met en place la push-capture) |
| 5 | Pion Épée → Pion Épée **ennemi** | combat |
| 6 | Bouclier → Pion Épée **allié** | coopératif |
| 7 | Bouclier → Pion Épée **ennemi** | combat — coup de bouclier |
| 8 | Bouclier → Épéiste **ennemi** | combat — déloge |

*Rappel règles (d'où l'absence des autres combinaisons) : l'Épéiste ne pousse QUE
ses alliés Épée/Bouclier et l'Épéiste ennemi ; un Bouclier n'est jamais poussé
sauf par son propre Épéiste ; un Pion Épée ne pousse jamais un Bouclier. Seuls
#4/#5 et #6/#7 ont une cible mixte → +2 clips.*

### ⚔️ Finish / fatalities (conditions de victoire)
| Anim | Ce qui se passe | Signature ? |
|---|---|---|
| Pion Épée capture l'Épéiste (direct) | arrive sur sa case → frappe → l'Épéiste s'effondre | ✅ cosmétique |
| Push-capture | Pion Épée *poussé* sur l'Épéiste adverse → porte le coup fatal | ✅ cosmétique |
| (Extension) Éjection | poussée hors plateau — **modes Sumo/custom du Labo seulement** | |

### La composition (le truc malin)
Tout se **compose** à partir de briques : `{pas}` × pièce, `{poussée coopérative}`
et `{bousculade combative}` × pousseur, `{recul}` × cible (consenti vs encaissé),
`{chute}` de l'Épéiste. Exemple : une **push-capture** = *poussée n°4*
(coopérative) + *chute de l'Épéiste* réutilisée. Un outil qui mélange les clips
(machines à états Rive / NLA Blender) réduit le travail réel d'animation.

---

## 6. Modèle de cosmétiques & branchement économie

### Loadout du joueur (hybride)
- **Niveau 1 — Set complet** : un look cohérent qui remplit tous les slots d'un
  coup (extension directe de WurmzSkin, qui habille déjà tout d'un seul skin).
- **Niveau 2 — Slots individuels** : casque / corps / épaules / jambes / sabre /
  garde, mixables **sur le combattant** (casque d'un set + armure d'un autre).

### Garde-robe : composer, sauvegarder, choisir ses anims
- **Composer** (« créer son skin ») : le joueur assemble son look **à partir des
  pièces qu'il possède** (1 choix par slot), avec **aperçu live** de son
  combattant, puis **sauvegarde** sous un nom. *Décidé le 2026-07-28 : compo pure
  — **pas** d'upload d'art perso ni de teinture pour l'instant (sain, sans
  modération).*
- **Presets** : plusieurs identités complètes sauvegardables (**look + anims**),
  qu'on **switche avant un combat**.
- **Sélecteur d'animations** : un panneau liste les clips débloqués **groupés par
  type** (Salut ×N, Fatality ×N, plus tard Pose de victoire…). Le joueur coche le
  **clip actif** de chaque type. L'aperçu réutilise **le même moteur d'assemblage**
  que le combat (le joueur voit SON combattant faire la fatality avant de choisir).
- **Sobriété** : seules les anims **expressives** sont échangeables (salut,
  fatality, pose de victoire). Les anims **fonctionnelles** (pas, poussées)
  **restent fixes** — la lisibilité du jeu prime (reconnaître une poussée au coup
  d'œil).

### Décomposition progressive (vendre des sets d'abord, des pièces ensuite)
Les **slots sont fins dès le départ** (casque, épaules, plastron, tassettes,
jambes, sabre…), mais la boutique **vend d'abord des bundles** (« tenue
complète » = plusieurs slots livrés d'un coup) et **les mêmes slots à la pièce
plus tard**. Un bundle n'est que plusieurs pièces de slots groupées → **aucun
refactor** le jour où on décompose.

### Sources d'obtention (branchées sur l'économie existante)
| Voie | Monnaie | Rappel |
|---|---|---|
| Jeu régulier | 🌿 Shiso, ⚔ Tamashii, 🏮 Mon, 🐉 Ryu | gagnés en mode |
| Constance | 🍄 Shiitake | boucle quotidienne |
| Événements | 🌸 Hanafuda | saisonnier |
| **Premium** | 石 **Koku** | ⛔ **jamais gagné en jouant** → parfait pour les skins premium |
| Paliers de mode | déblocage de contenu | `claimMilestone()` prévoit déjà un déblocage |

Raretés proposées (à affiner en session « éco des skins ») — échelle
thématique : **Ashigaru** (commun) → **Samouraï** (rare) → **Daimyō** (épique)
→ **Shōgun** (légendaire).

### Données (Supabase) — modèle figé le 2026-07-28

**Catalogue — `skin_catalog`** *(contenu géré par admin)*. Un item = une pièce
visuelle, une animation, ou un bundle.
| Colonne | Rôle |
|---|---|
| `id` (text slug) | ex. `casque_kabuto_or`, `fatality_iai_01` |
| `kind` | `cosmetic` \| `animation` \| `bundle` |
| `slot` | cosmetic : `tenue_base\|casque\|epaules\|plastron\|tassettes\|jambes\|sabre\|garde\|embleme\|aura` · animation : `salut\|fatality\|victoire` |
| `name`, `rarity` | `ashigaru\|samourai\|daimyo\|shogun` |
| `source` (jsonb) | **où/quoi se gagne** — *paramétrable admin (point éco, différé)* : `{type:'shop',currency:'koku',cost:500}`, `{type:'milestone',mode:'arene',palier:150}`… |
| `grants` (text[]) | bundle → la liste des ids débloqués d'un coup |
| `asset_ref` | l'artboard / skin Rive-Spine |
| `premium`, `active` | drapeaux |

RLS : **lecture publique**, **écriture admin** (`is_admin_user()`).

**Possession — `player_items`** `(player_id, item_id, acquired_at, source)`,
PK(player_id, item_id). RLS : le joueur **lit les siens** ; **aucun INSERT
client** → octroi **uniquement par RPC** `SECURITY DEFINER` (leçon Ryu de guilde :
la possession n'est jamais sur parole du client).

**Presets — `player_presets`** `(id, player_id, name, slots jsonb {slot:item_id},
anims jsonb {type:item_id})`. RLS : plein accès aux siens.

**Loadout actif public — `profiles.equipped_loadout jsonb`** : le look+anims
actifs, dénormalisés pour l'affichage (carte de combattant, lobby). Lecture
publique ; écriture via RPC `set_active_loadout` qui **valide la possession**.

**RPC (possession / monnaie = serveur)**
- `skin_purchase(item_id)` — vérifie le coût, **débite la monnaie**, insère
  (bundle → octroie tous ses `grants`).
- `skin_grant(player_id, item_id, source)` — octroi serveur (paliers, saison,
  événement).
- `set_active_loadout(preset)` — **valide la possession**, écrit `equipped_loadout`.
- Admin (`is_admin_user()`) : `skin_catalog_upsert(…)`, `skin_set_source(…)` —
  **c'est ici que se paramètre « où/quoi se gagne »** (point 1, prêt mais différé).

**Anti-triche — 3 règles**
1. Possession + monnaie = **serveur only** (jamais d'INSERT client → sinon premium
   gratuit, la faille Ryu de guilde vécue).
2. **Équiper valide la possession** (pas de premium affiché sans l'avoir).
3. **Afficher l'adversaire = depuis le snapshot** de la partie (jamais son
   inventaire → zéro lecture croisée).

### Voyage du loadout en partie — **tranché : snapshot**
`online_games.loadouts jsonb` (**nullable, additive**, lu via `select('*')` — règle
CLAUDE.md) = `{white:{…}, black:{…}}`, comme `custom_format` en M5③. **Chaque
joueur estampille SA couleur** depuis son propre `equipped_loadout` (le créateur
pose `white` à la création, l'adversaire pose `black` à l'entrée) → **personne ne
contrôle le look de l'autre**. Avantages :
- **Fidélité rejeu/spectateur** : le look d'alors est figé même après un
  changement de preset.
- **Confidentialité** : afficher l'adversaire ne lit que le snapshot, jamais son
  inventaire/profil.
- Ne contient que des **ids** (les assets sont livrés avec l'app) → charge minime,
  posé **une fois** sur la colonne (pas reconduit à chaque coup, contrairement au
  format).

---

## 7. Runtime d'assemblage

Au rendu d'une pièce pour le joueur X : lire le loadout de **son combattant** →
**empiler les couches par slot** (identité du guerrier + slots concernés) →
jouer le clip d'anim adéquat (avec override *signature* éventuel). Idem pour
l'adversaire depuis son loadout.
C'est **exactement** le modèle skins/attachments de Rive/Spine — leur runtime
fait la composition pour nous. On ne pré-cuit jamais une combinaison entière.

## 8. Roadmap du sous-projet

- **Phase 0 — Fondation** *(ce doc)* : rig spec + slots + catalogue d'anims +
  choix d'outil. **Puis** : Thomas dessine **1 combattant test** avec 2
  cosmétiques alternatifs par slot (pour valider le pipeline découpe→squelette).
- **Phase 1 — Assembleur** *(en cours)* : prouver l'**assemblage modulaire par
  slots** en direct dans le navigateur, avec placeholders **dessinés dans le
  code** (zéro art de Thomas). Cible du proto : **deux samouraïs qui se font
  face** — **blanc/sabre rouge** vs **noir/sabre bleu** — sur **un squelette
  2.5D partagé**, slots échangeables en direct (la compo se recompose), sélecteur
  d'anim (**salut / idle-réflexion / fatalité**) et **micro-anim des yeux**
  (ils se plissent en réflexion). But : démontrer d'un coup **la règle d'or**
  (l'anim porte n'importe quel équipement) **et** la promesse manga.
  Fichier : `avatars/proto.html` (autonome, sans dépendance, sans Supabase).
- **Phase 2 — Animation** : monter les **~20 gestes** sur le squelette commun.
- **Phase 3 — Économie & boutique** : modèle de données cosmétiques, obtention
  (monnaies), vitrine, loadout persistant.
- **Phase 4 — Intégration jeu** : brancher sur le rendu du plateau, généraliser
  / remplacer WurmzSkin, faire voyager le loadout (cf. §6).

## 9. Décisions en attente

1. **Cible du rendu** : pré-rendu par couches vs runtime live (penche live).
2. **Rive vs Spine** : dépend du budget (Rive gratuit à petite échelle / Spine
   payant mais référence). Choix après un test dans chacun.
3. ✅ **Voyage du loadout** : *tranché* — snapshot figé dans
   `online_games.loadouts` (chaque joueur estampille sa couleur) + `profiles.
   equipped_loadout` pour l'affichage public. Cf. §6.
4. **Éco des skins** : raretés, prix, sources exactes, saisons de skins.
5. **Vue de plateau** : angle 3/4 exact, taille des combattants sur la case,
   lisibilité en 5×5 (ne pas encombrer le plateau).

### Tranchées le 2026-07-28 (session « éclaircissements »)
6. ✅ **Le visage entre dans le squelette gelé** (paupières/sourcils/mâchoire) →
   micro-anims façon manga. Casques en overlay. Cf. §4.
7. ✅ **« Points de vue » = plans montés, pas caméra 3D libre.** La réal manga
   passe par des cadrages d'auteur. Cf. §4.
8. ✅ **Pipeline de production acté** : Thomas dessine en **vue ¾, en pièces
   séparées** (calques) → une **passe de rigging humaine dans l'éditeur**
   (lourde une seule fois pour le squelette de base, légère ensuite : « dessiner
   la pièce + l'accrocher à l'os »). **Pas d'auto-génération** d'un skin à partir
   d'un dessin brut (les auto-rig inventent leur propre squelette → cassent la
   règle d'or). Le *proto* utilise des placeholders dessinés dans le code, donc
   **zéro art et zéro engagement** avant validation. Cf. §8, Phase 1.

---

*Rédigé le 2026-07-28. Fait suite à la décision « hybride » + 2.5D squelettique.
Prochaine action naturelle : valider ce découpage de slots avec Thomas, puis
Phase 0 (combattant test) ou Phase 1 (proto d'assembleur).*

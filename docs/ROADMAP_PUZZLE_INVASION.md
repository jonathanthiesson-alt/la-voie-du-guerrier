# Roadmap — Mode PUZZLE (Dojo) & Mode INVASION (Monban)

> Cadrage rédigé le 2026-08-16, **avant** toute ligne de code.
> Les décisions du § 2 sont **figées** (valid.ées par Wurmz le 2026-08-16) : ne
> pas les rouvrir sans raison — re-débattre une décision d'archi en plein lot
> coûte plus cher que de la coder.
> Chaque lot livré complète le § 6 (points d'entrée) : c'est ce qui évite de
> refouiller `index.html` (1,2 Mo) à chaque session.

---

## 1. Ce que le code offre déjà (vérifié, pas supposé)

Ces deux modes sont surtout de l'**assemblage**. Presque toutes les briques
existent.

| Besoin | Ce qui existe déjà | Où |
|---|---|---|
| Éditeur visuel (dimensions, cases mortes, pose de pièces) | `labEd*`, `labEdCurrentFormat()` → `{name,rows,cols,v2,sumo,voids,pieces,setup}` | ~20440-20500 |
| Validation d'un format | `labValidateFormat()` — borne déjà rows/cols à 3-9 | ~20338 |
| Moteur jetable pour aperçu | `labMakePreviewEngine(format)` (`new Function`, zéro dérive) | ~20449 |
| Rendu agnostique aux dimensions | `isValid`/`renderBoard` lisent `G.rows`/`G.cols` | — |
| Registre de formats publiés | table `dev_published_formats` + RPC publish/delete | SQL |
| Format qui voyage jusqu'aux 2 clients | `game_state.format`, `settings._customFormat` | — |
| IA qui profile le joueur | `NT2_PROFILE` (skillRating, weaknesses, minimax) | ~9595-9880 |
| Bot qui joue une VRAIE partie online | worker `scripts/bot-army.mjs` (GitHub Actions) | repo |
| Monnaies | 8 colonnes `<cur>_balance` (koku, shiso, tamashii, mon, ryu, hanafuda, shiitake, fame) | `profiles` |
| Transfert de monnaie atomique | modèle `spend_koku` / `unlock_skin_pack` (RPC `SECURITY DEFINER`) | SQL |
| Présence | `presenceTier()` → online / away / offline | ~25967 |
| Notifications + badges village | table `notifications`, skill `/lvdg-notifications-audit` | — |
| Journal du joueur | livré V0.87.0 — point d'écriture idéal pour les invasions subies | ~10520 |

**Le descripteur de puzzle = format Labo + 3 blocs neufs** (`objective`, `ai`,
`timer`). Rien d'autre. C'est la clé de voûte du mode.

### ⚠️ Deux trous trouvés pendant l'analyse

1. **`presenceTier()` ne renvoie jamais `'combat'`**, alors que
   `.presence-badge.is-combat` est défini et stylé (CSS ~1774) : état mort
   (défaut n°6 de `/lvdg-ui-optimiser`). Or l'invasion en direct a besoin de
   savoir si le joueur est déjà en partie → **à implémenter, pas à réutiliser**.
   Note aussi : `presenceTier` se base sur `last_seen ≤ 3 min`, donc on peut
   viser quelqu'un parti depuis 2 min 59 — le repli Monban (décision D) absorbe ça.

2. **Le panneau de bâtiment du village n'a qu'UN niveau.** `villageOpenBuilding()`
   affiche une liste plate d'items ; il n'existe aucun sous-menu. La décision E
   (3 portes d'intention) impose donc de **construire un 2ᵉ niveau de panneau** —
   c'est un vrai petit chantier UI, à absorber dans la passe `/lvdg-ui-optimiser`
   du Dojo, pas à découvrir en cours de route.

---

## 2. Décisions figées (2026-08-16)

| # | Décision | Conséquence technique principale |
|---|---|---|
| **A** | **L'IA des puzzles est strictement déterministe** : `luck:0`, profondeur fixe, départage déterministe. | Il faut un mode « déterministe » du moteur et surtout **un ordre de génération des coups stable** (`allMoves`) — sinon le départage à score égal varie et le puzzle n'est plus reproductible. À vérifier explicitement en P0. |
| **B** | **Monban tourne sur le serveur** (worker `bot-army` étendu). Le serveur arbitre le résultat. | Le profil vit dans `monban_profiles` ; le worker le lit et joue avec. ⚠️ Piège vécu : toute nouvelle dépendance du moteur doit être ajoutée à `ENGINE_NAMES` de `scripts/bot-army.mjs`, sinon les bots rejoignent sans jamais jouer (`ReferenceError` silencieux). Nécessite une file `invasion_queue` sur le modèle de `matchmaking_queue`. |
| **C** | **La limite 1/24 h est côté ATTAQUANT.** Un défenseur peut être envahi plusieurs fois par des joueurs différents. Le bouclier est une vraie protection, donc un vrai produit boutique. | `profiles.last_invasion_at` (attaquant) + `profiles.shield_until` (défenseur). Bouclier obtenu en perdant **ou** acheté en Koku. |
| **D** | **Invasion en direct : 15 s pour accepter, sinon Monban prend le relais.** | Canal temps réel + minuteur d'acceptation ; à l'expiration, bascule vers le chemin serveur (décision B). Impose `presenceTier` complété avec `'combat'`. |
| **E** | **Dojo réorganisé en 3 portes d'intention** : « S'entraîner » (Défi du jour, Karakuri, Tuto, Adversaires, Notables) · « Créer » (Puzzle) · « Défendre » (Monban, Invasion). | Impose le **2ᵉ niveau de panneau village** (cf. § 1, trou n°2). Passe `/lvdg-ui-optimiser` obligatoire avant de coder. |
| **F** | **Elo du puzzle** : modèle type Lichess (le puzzle est un « joueur » avec rating + incertitude qui se resserre), calibré contre l'Elo du joueur **dans la cadence du puzzle**. V1 minimale acceptable : moyenne mobile réussite/échec. | Dépend entièrement de A. Rating de départ estimé à la publication. |
| **G** | **Anti-farm** : gain **au premier achèvement de chaque joueur unique**, plus un **plafond quotidien** de gains par créateur. | Table `puzzle_completions(puzzle_id, user_id)` avec contrainte UNIQUE + compteur journalier. |
| **H** | **Modération obligatoire** : signalement joueur + dépublication admin. Condition d'ouverture publique, pas une finition (exigence App Store / Play Store, AXE 5). | À prévoir dès la conception de la table `puzzles`, pas après. |
| **K** | **Sélecteur de tranche explicite** à l'invasion (à mon niveau / +150 / +300…), butin annoncé en face. Le ±100 devient le défaut. | Paramètre passé au matchmaking d'invasion. |
| **M** | **L'Elo de Monban est dérivé du mien** (éventuellement léger malus), pas un Elo indépendant. | Aucune colonne Elo à maintenir : on lit `profiles.elo_Xs`. Matchmaking d'invasion trivial. |
| **N** | **Slot = puzzle publié SIMULTANÉMENT.** La dépublication libère le slot (l'Elo et l'historique sont conservés). | `puzzles.published boolean` + comptage des publiés par joueur. |
| **O** | **Monban apprend de TOUTES mes parties en ligne.** L'entraînement quotidien est un rituel bonus. | Hook en fin de partie (là où le Journal écrit déjà) qui alimente le modèle. Le modèle doit rester **compact** (jsonb) : ouvertures jouées, agressivité, profil de faiblesses — sur le patron de `NT2_PROFILE`, mais en base. |
| **I/J** | **Le VAINQUEUR choisit la monnaie** (l'envahisseur s'il gagne, le défenseur s'il repousse). Si le perdant est à 0 dans cette monnaie, **prélèvement automatique sur sa monnaie la mieux fournie**. Jamais de Koku. | RPC `SECURITY DEFINER` unique qui fait le transfert atomiquement, sur le modèle de `spend_koku`. |
| **S** | **Quitter un combat d'invasion = défaite**, des deux côtés. | Bouche l'exploit majeur : sans ça, un envahisseur en train de perdre quitte pour ne pas payer. ⚠️ Impose une **fenêtre de reconnexion** (~45 s) avant de déclarer l'abandon — sinon un tunnel de métro coûte de la monnaie. Comme le serveur arbitre (décision B), il peut tenir la partie en attente. ⚠️ Un défenseur qui a **accepté** puis quitte perd : il ne bascule PAS sur Monban (sinon « je perds → je quitte → mon gardien me sauve » devient une martingale). |
| **V** | **Aucune cible trouvée → on s'arrête immédiatement** (pas d'élargissement automatique de la fenêtre d'Elo) et **la tentative du jour n'est PAS consommée**. | Le joueur obtient exactement la tranche qu'il a demandée. L'élargissement existe déjà, mais **manuel** : c'est le sélecteur de tranche (décision K) qui joue ce rôle — le joueur choisit sciemment de viser plus haut. Ne jamais décrémenter le quota sur un échec de recherche. |
| **W** | **Délai de ~72 h par couple de joueurs** : je ne peux pas réenvahir la même personne avant expiration. | Anti-harcèlement. Le matchmaking exclut de mes cibles les joueurs envahis récemment (table `invasion_history(attacker_id, defender_id, created_at)`). Réduit d'autant le vivier — cf. § 6, risque alpha. |
| **T** | **Statistiques publiques par puzzle** : parties jouées, réussies, échouées, taux de réussite, note moyenne. Plus une vue créateur enrichie (« historique de mes puzzles »). | Compteurs dénormalisés sur `puzzles` (lecture rapide de la liste) + détail dans `puzzle_attempts`. **Même pipeline que l'Elo du puzzle** (décision F) : le taux de réussite alimente les deux, on ne construit la collecte qu'une fois. |
| **U** | **Note 5 étoiles**, proposée **après le premier achèvement réussi**, une note par joueur (modifiable). Pas de commentaire libre en V1. | Réserver la note aux joueurs qui ont réussi évite le vote-sanction des puzzles difficiles et le brigandage (un rival ne peut pas 1-étoiler sans jouer). La note vit dans `puzzle_attempts`/`puzzle_completions`. Masquer la moyenne sous 3 votes (évite le « 5 étoiles (1 avis) »). Pas de commentaire = pas de modération de texte à construire. |

### Points que je pars pour appliquer, sauf objection

| # | Position retenue | Pourquoi |
|---|---|---|
| **L** | **Non envahissable pendant un tournoi ou un défi de guilde.** | Être tiré dans une invasion entre deux rondes fait rater sa ronde → forfait. Le risque est trop asymétrique. |
| **R** | **Jouer un puzzle utilisant une option non débloquée est TOUJOURS possible** (jouer ≠ créer). | Sinon la moitié du catalogue devient invisible et le mode s'étouffe tout seul. Le déblocage porte sur la **création**. |
| **P** | Les puzzles et leur Elo **survivent** au reset de saison. La monnaie puzzle suit le sort des autres monnaies de mode (conversion Koku + remise à zéro, décision structurante n°3). | Un puzzle est une création, pas un score de saison. |
| — | **Modes coupables dès le départ** : Puzzle et Invasion naissent avec leur drapeau `guardFeature`. | Décision structurante n°6 : pouvoir couper un mode qui bugue sans redéployer, vital une fois sur les stores. |
| — | **Nommage figé en fr/en/ja au 1er commit** : **Monban** (門番). | Le projet a déjà payé cet oubli avec « Combattant ». (Pour mémoire, l'IA existante s'écrit `Ningen-Two` / 人間二.) |

---

## 3. Découpage en lots

Le risque est mis en tête, et chaque lot reste livrable seul. **Un lot = une
session de travail.**

### Mode PUZZLE

| Lot | Contenu | Dépend de |
|---|---|---|
| **P0** | Socle : table `puzzles` (modération incluse dès le départ), énumération des objectifs, **moteur déterministe + ordre de coups stable**. 1 script SQL. | A, H |
| **P1** | Éditeur joueur — réutilise `labEd*` tel quel, sorti du Labo dev vers un écran joueur. 100 % local, aucun réseau. | P0 |
| **P2** | Tester + **preuve de réussite** (enregistrement de la séquence gagnante). | P1, A |
| **P3** | Publier + liste + **miniature rendue à la volée** (`labMakePreviewEngine`, zéro image stockée) + tri/filtres. | P2, N |
| **P4** | Jouer le puzzle d'un autre + achèvement + **collecte des tentatives** (succès/échec) → alimente Elo ET stats d'un seul geste. | P3, F |
| **P5** | **Stats & notation** : note 5 étoiles après réussite, compteurs publics sur la page d'aperçu, écran « historique de mes puzzles » côté créateur. | P4, T, U |
| **P6** | Économie : monnaie puzzle, slots, boutique, anti-farm. | P5, G |
| **P7** | Déblocables de création (borderless via saison Sumo, etc.). | P6, R |
| **P8** | Modération : signalement + dépublication admin. **Bloquant avant ouverture publique.** | P3 |

### Mode INVASION

| Lot | Contenu | Dépend de |
|---|---|---|
| **I0** | `monban_profiles` + apprentissage depuis **toutes** mes parties. Généralise `NT2_PROFILE` vers la base. | O, M |
| **I1** | Écran Monban : consulter (Elo, stats) / entraîner / personnaliser (skins). | I0, E |
| **I2** | **Défense serveur via le worker** — chemin critique, c'est là qu'est l'anti-triche. | I0, B |
| **I3** | Invasion : file, sélecteur de tranche, matchmaking ±100, repli sur Monban hors ligne. | I2, K |
| **I4** | Invasion en direct : `presenceTier` + `'combat'`, fenêtre d'acceptation 15 s, repli Monban. | I3, D |
| **I5** | Économie du vol (RPC atomique) + bouclier + **abandon = défaite** (fenêtre de reconnexion) + gains/pertes à l'écran de fin. | I4, C, I/J, S |
| **I6** | **Notifications** (§ 4) + écriture au Journal du joueur. Passe `/lvdg-notifications-audit` obligatoire. | I5 |

### Ordre conseillé entre les deux modes

**P0 → P3 d'abord** (autonome, sans temps réel, risque faible, livrable vite),
puis **I0 → I2** (le worker est le vrai morceau d'ingénierie), puis alterner.

⚠️ Ne pas démarrer **I4** avant que **I2** soit validé en conditions réelles —
sinon on empile deux inconnues sur le chemin critique.

⚠️ La passe `/lvdg-ui-optimiser` sur le Dojo (décision E + 2ᵉ niveau de panneau)
doit passer **avant P1 et avant I1**, puisque les deux modes y accrochent leurs
écrans.

---

## 4. Notifications (lots I6 et P5)

Types à créer. Chacun doit passer les **6 points de câblage** du skill
`/lvdg-notifications-audit` (insertion SQL, icône, `notifCatColor`, routage au
clic, pastille menu classique, **pastilles village**) — un type oublié quelque
part ne casse rien visiblement, il devient juste invisible.

| Type | Quand | Catégorie | Clic → |
|---|---|---|---|
| `invasion_defended` | Monban a repoussé une invasion en mon absence (je gagne) | Jeu | Écran Monban |
| `invasion_lost` | J'ai été envahi et dépouillé | Jeu | Écran Monban (+ Journal) |
| `invasion_missed` | Invasion en direct que je n'ai pas acceptée à temps (Monban a pris le relais) | Jeu | Écran Monban |
| `shield_expired` | Mon bouclier vient d'expirer | Système | Boutique (rachat) |
| `puzzle_completed` | Un joueur a terminé mon puzzle (gain de monnaie) | Jeu | Historique de mes puzzles |
| `puzzle_rated` | Mon puzzle a reçu une note | Jeu | Historique de mes puzzles |
| `puzzle_reported` | Un de mes puzzles a été signalé / dépublié | Système | Historique de mes puzzles |

⚠️ **Anti-spam** : `puzzle_completed` et `puzzle_rated` peuvent devenir
bruyants sur un puzzle populaire. Les **agréger** (« 12 joueurs ont terminé tes
puzzles aujourd'hui ») plutôt qu'une notification par événement.

### 🔴 Problème de conception à régler ici, pas plus tard

`villageRefreshBadges()` filtre les pastilles de bâtiment avec **deux
allowlists codées en dur** : Arène = `['challenge','tournament_game']`,
Auberge = `['message','friend_request']`. C'est le piège n°1 documenté du
skill notifications.

Avec le Dojo qui doit maintenant porter ses propres pastilles (invasion,
puzzle), on ajouterait une **troisième** liste en dur. Le motif ne passe
manifestement pas à l'échelle.

**Correctif de fond recommandé, à faire en I6 :** rendre la correspondance
**pilotée par les données** — chaque bâtiment de `VILLAGE_BUILDINGS` déclare
les types de notification qui l'incrémentent, et `villageRefreshBadges()` lit
cette déclaration. On supprime le piège définitivement au lieu de le nourrir
une fois de plus (c'est exactement la logique « altitude » : généraliser le
mécanisme plutôt qu'empiler les cas particuliers).

---

## 5. Économie de tokens

Le coût dominant n'est pas d'écrire le code : c'est de retrouver **où**
l'écrire dans 1,2 Mo, et de re-expliquer le contexte à chaque session.

1. **Consigner les points d'entrée** (§ 6) à chaque lot livré. La session
   suivante démarre sur une carte, pas sur une fouille.
2. **Ne jamais relire `index.html` en entier** — un `Read` sans borne dépasse
   déjà la limite de contexte (rencontré le 2026-08-16). Toujours : grep ciblé
   → `Read` avec `offset`/`limit`.
3. **1 lot = 1 session.** Un lot qui déborde paie deux fois la remise en contexte.
4. **Le SQL en amont et groupé** : un script par lot, écrit et exécuté au début.
   Les « ah, il manque une colonne » en cours de route sont le pire cas — et le
   piège Supabase n°1 du projet (tout le script est annulé si la dernière
   instruction échoue).
5. **Les décisions sont figées au § 2.** Les rouvrir coûte plus cher que de les coder.
6. **Réutiliser plutôt que réécrire.** Chaque ligne de l'éditeur Labo réécrite
   pour le puzzle est payée deux fois et devient un doublon à maintenir
   (défaut n°5 de `/lvdg-ui-optimiser` : le bloc dupliqué).
7. **Les skills portent la méthode** pour ne pas la ré-expliquer :
   `/lvdg-ui-optimiser` (Dojo), `/lvdg-notifications-audit` (nouveaux types de
   notif), `/lvdg-audit-vibration`.

---

## 6. Risques ouverts (à surveiller, pas à trancher maintenant)

- **Équilibre du butin.** « 1 unité volée » est-il ressenti comme un enjeu, ou
  comme un détail ? À calibrer contre les gains d'une partie normale une fois
  I5 jouable. Trop faible = personne n'envahit ; trop fort = harcèlement.
- **Le worker devient central.** Bot-Army, Ligue, tournois, guildes et
  maintenant Invasion en dépendent. Une panne prolongée de GitHub Actions
  toucherait désormais un mode à enjeu économique. Prévoir le comportement en
  cas de worker absent (invasions en attente, pas de vol fantôme).
- **Volume de `monban_profiles`.** Un profil par joueur, mis à jour à chaque
  partie : garder le modèle compact et borner l'historique conservé.
- **Puzzles et évolution du moteur.** Un puzzle publié aujourd'hui doit rester
  solvable si le moteur évolue. Versionner le descripteur (`format.v`) dès P0.
- **Volume de `puzzle_attempts`.** Une ligne par tentative (et non par
  achèvement) sur un puzzle populaire, ça grossit vite. Garder la table étroite
  et s'appuyer sur les compteurs dénormalisés pour tout affichage de liste.
- **Notes en trop faible nombre.** Tant qu'un puzzle a moins de 3 notes, la
  moyenne n'a aucune valeur statistique — l'afficher quand même donnerait un
  faux signal de qualité dans le tri.
- **🔴 Vivier d'invasion trop petit en alpha.** Quatre filtres se cumulent :
  tranche d'Elo stricte (V), délai de 72 h par couple (W), boucliers actifs (C),
  et exclusion des joueurs en tournoi (L). À une dizaine de comptes actifs, il
  est très possible que « aucune cible » devienne la réponse habituelle.
  **À mesurer dès que I3 est jouable** — si le mode tourne à vide, les leviers
  dans l'ordre : raccourcir le délai par couple, ouvrir les Monban des bots de
  l'Armée des 15 comme cibles (butin réduit), ou assouplir la tranche par
  défaut. Ne rien pré-construire tant qu'on n'a pas la mesure.

---

## 7. Points d'entrée (à remplir au fil des lots)

### Dojo restructuré en 3 portes — LIVRÉ, vérifié 3x (2026-08-16, V0.93.0)

- `VILLAGE_BUILDINGS` entrée `dojo` (~ligne 12757) : 3 portes `door:true`
  (« S'entraîner », « Créer », « Défendre »). Puzzle/Monban/Invasion posés en
  `soon:true` (aucun lien mort).
- `villageOpenDoor(buildingId, doorIdx)` (nouvelle fonction, ~ligne 13034) —
  2e niveau de panneau générique, réutilisable par tout futur bâtiment.
- `villageOpenBuilding()` étendu : un item `door:true` route vers
  `villageOpenDoor()` au lieu de `villageDoItem()`.
- Vérifié : syntaxe, brace-depth, aucun doublon, `docs/SITEMAP.md` régénéré,
  test navigateur (ouverture des 3 portes, raccourci mono-item de « Créer »,
  navigation Karakuri + retour via `villageMenuReturn()`).
- « Défi du jour » retiré du Dojo (doublon du raccourci village 🎯).

### Socle SQL PUZZLE (P0) — EXÉCUTÉ en base (2026-08-16)

- `sql_a_executer/puzzles_core.sql` : 5 tables + RPC (détail dans
  `docs/SQL_MIGRATIONS.md`). Vérifié en base via MCP.

### Socle SQL INVASION/Monban (I0) — EXÉCUTÉ en base (2026-08-16)

- `sql_a_executer/monban_core.sql` : 3 tables + RPC d'apprentissage/bouclier.
  Vérifié en base via MCP.
- **Volontairement absent de ce script** : toute RPC qui ferait jouer Monban
  ou trancherait une invasion (lot I2, worker `scripts/bot-army.mjs` — pas
  encore écrit). Les construire sans le pilotage serveur reviendrait à
  ouvrir le trou de triche identifié en décision B.

### Éditeur de puzzle joueur (P1/P2/P3-partiel) — LIVRÉ, vérifié en navigateur

- **Généralisation du Labo, pas duplication** : `#lab-ed-widget` (nouveau,
  ~ligne 2986) regroupe le markup de l'éditeur (`lab-ed-dims/toolbar/board/
  info/types/typeform`) en un nœud DOM détaché, déplacé d'un écran à l'autre
  via `labEdMountWidget(targetId)` (nouvelle fonction, `appendChild` —
  aucune fonction `labEd*` existante n'a été modifiée). Le Labo dev l'utilise
  toujours exactement comme avant (`labShowTab('creer')` le remonte chez lui).
- `screen-puzzle-hub` (Dojo > Créer > Puzzle) : Jouer (`soon`, pas encore
  construit) / Créer.
- `screen-puzzle-editor` : 3 sous-onglets `pzShowTab()` — Créer/Modifier
  (éditeur + titre + objectif + cadence + `pzSaveDraft()`), Tester
  (`pzTestPuzzle()` — vraie partie locale contre une IA **strictement
  déterministe**, `minimaxPlay(...,3,evalTrainer,...)`, aucun hasard),
  Mettre en ligne (`pzPublish()`/`pzUnpublish()`, bloqué tant que
  `puzzle_set_solution` n'a pas été appelé — décision A/N).
- `endGame()` : branche `G._puzzleTestActive` en tête (même pattern que
  `G.arenaMatchId`) → `pzHandleTestEnd()`, qui reconstruit la solution
  depuis les instantanés `HISTORY` et court-circuite tout le flux normal
  (aucune stat/XP/succès n'est touchée par une partie de test).
- **Bug trouvé et corrigé pendant la vérification** : le drapeau
  `G._puzzleTestActive` était posé AVANT `initGame()`, qui réassigne `G` à un
  objet neuf (`G={...}`) — le drapeau était donc silencieusement perdu.
  Déplacé après l'appel. Sans le test navigateur, ce bug serait passé.
- **2e bug trouvé via `node scripts/sitemap.mjs`** : le retour de
  `screen-puzzle-hub` appelait `showScreen('village')` en dur (carte nue) au
  lieu de `showScreen('menu')` (intercepté par `villageInterceptBack()` →
  rouvre le panneau Dojo). Corrigé, carte régénérée propre.
- Vérifié en navigateur (mocks `supa.rpc`/`supa.from`, réseau non exécuté
  contre la prod) : brouillon → test → victoire simulée → solution capturée
  → publication bloquée puis débloquée → dépublication. Vérifié aussi que le
  Labo dev n'est pas cassé (widget se replace correctement).

### Jouer les puzzles des autres (P3/P4 socle) — LIVRÉ, vérifié en navigateur (V0.95.0)

- `screen-puzzle-browse` (Dojo > Créer > Puzzle > Jouer) : `pzLoadBrowseList()`
  liste les puzzles `published=true`/`status='active'`, triés par
  `play_count`. Pas de miniature rendue (P3 « vraie » liste tri/filtres
  reste à faire), pas de vue créateur enrichie.
- `pzPlayPuzzle(id)` : relit `format/ai/timer_seconds` du puzzle visé,
  lance une vraie partie locale contre l'IA **du créateur** (profondeur
  stockée dans `puzzles.ai`, toujours `luck:0`) — même schéma que
  `pzTestPuzzle()` mais généralisé à un id quelconque, slot IA 98 partagé.
- `endGame()` : branche `G._pzPlayId` (juste après `G._puzzleTestActive`) →
  `pzHandlePlayEnd()`, qui appelle `puzzle_record_attempt` (compte l'essai,
  met à jour Elo/compteurs côté serveur en un seul geste — décision F/T) et,
  en cas de victoire, propose la notation 5 étoiles (`pzOfferRating` →
  popup `#pz-rate-popup` → `puzzle_rate`, décision U).
- Vérifié en navigateur (mocks) : liste rendue avec note/compteurs → partie
  lancée avec la bonne profondeur/cadence → victoire → `puzzle_record_attempt`
  appelé avec le bon `p_success`/`p_player_elo` → popup 5 étoiles → note
  soumise → défaite → pas de popup. Retour `puzzle-browse → puzzle-hub`
  vérifié cohérent (`node scripts/sitemap.mjs`, aucune régression).

### Monban — consulter/entraîner (I0/I1 socle) — LIVRÉ, vérifié en navigateur (V0.96.0)

- `screen-monban-hub` (Dojo > Défendre > Monban), plus `soon:true`.
  Affiche mon Elo (décision M : **pas** d'Elo indépendant, réutilise
  `buildEloGridHtml(currentUser)` telle quelle) + `monban_stats`
  (défenses gagnées/perdues) + `monban_profiles` (parties apprises, dernier
  entraînement). Bouton `monbanTrainToday()` → RPC `monban_mark_trained`.
  **Changé le 2026-08-18 (V0.112.0, décision Wurmz)** : le clic quotidien ne
  donne plus un +2 instantané — `monban_mark_trained()` ne fait plus que
  poser la garde 1×/jour (admin bypass inchangé), et déclenche un vrai duel
  local (`monbanStartTrainingDuel(cadence)`, adversaire local id 13 dans
  `ADVERSARIES`, couleur tirée au sort via `startCoinFlipSequence`, sans
  passer par `showColorPicker`) contre son propre Monban. `monbanTrainingPlay`
  rejoue localement la même logique de clone que l'Edge Function `monban-move`
  (profil préchargé dans `_monbanTrainingProfile`, synchrone). Résultat
  appliqué en fin de partie (`endGame()`, garde `_monbanDuelCadence`) via la
  nouvelle RPC `monban_apply_training_duel(cadence, monbanWon)` :
  Monban gagne → +7/+5/+3 selon la cadence (3s/5s/10s) ; Monban perd →
  aucune perte, bonus pur. SQL : `sql_a_executer/monban_training_duel.sql`.
- `monbanRecordGameResult(playerWon)` : câblée dans `endGame()`, juste
  après le `logJournalEvent` online existant (même garde `G.onlineGameId`).
  **V1 minimale, décision prise avec Wurmz avant de coder** : pas de suivi
  fin coup par coup (exposure/missedWin/passivity) pour les parties en
  ligne — ce suivi n'existe aujourd'hui QUE pour NT2 en local
  (`nt2AnalyzePlayerMove`), l'instrumenter en ligne est un chantier à part
  entière, pas absorbé dans cette passe. À la place : `skillRating` ajusté
  de +3 (victoire) / -1 (défaite, plus prudent que NT2 car signal plus
  grossier), plus la première case atteinte par mon Combattant accumulée
  dans `openings`. Poussé via `monban_learn_from_game` (RPC existante,
  fusion superficielle côté serveur).
- Cache client `_monbanProfileCache` (évite une lecture réseau par partie ;
  invalidé après chaque écriture) — même idée que `NT2_PROFILE` mais côté
  serveur.
- Vérifié en navigateur (mocks) : écran → Elo + stats affichés correctement
  → entraînement du jour → RPC appelée, statut affiché → simulation d'une
  partie en ligne gagnée → `skillRating` 53→56, ouverture enregistrée,
  aucune erreur.

### Invasion complète (I2-I6) — LIVRÉE, vérifiée (mocks) — V0.97.0

**Architecture retenue, décidée pendant l'implémentation (pas dans les
décisions A-W figées le 2026-08-16, donc documentée ici) : une invasion EST
une partie `online_games` normale, taguée `is_invasion` — pas une
infrastructure parallèle.** L'envahisseur joue TOUJOURS Blanc, le défenseur
TOUJOURS Noir (simplification V1 : le moteur worker n'a besoin de piloter
qu'un seul camp fixe). Ce choix a permis de réutiliser tel quel
`enterOnlineGame`/`subscribeToOnlineGame`/l'écriture de fin de partie — zéro
duplication de l'infrastructure de partie en ligne.

- **SQL** (`sql_a_executer/invasion_engine.sql`, **exécuté via MCP,
  vérifié**) : colonnes `online_games.is_invasion/invasion_attacker_id/
  invasion_defender_id/invasion_resolved`, table `invasion_requests`
  (fenêtre d'acceptation 15s), 7 RPC. **Garde de sécurité vérifiée en base**
  (`has_function_privilege`) : `invasion_resolve_internal` (le transfert de
  monnaie + notifs + stats + journal) a l'EXECUTE révoqué pour
  `authenticated`/`anon` — seul `service_role` (le worker) ou
  `invasion_forfeit` (auto-déclaration de SA PROPRE défaite, donc non
  exploitable) peuvent l'atteindre.
- **Worker** (`scripts/bot-army.mjs`, `driveInvasions()`) : 3 passes —
  expire les demandes non répondues après 15s → `monban` ; joue les coups de
  Monban (profondeur dérivée de `monban_profiles.skillRating`, même formule
  que NT2) et résout la partie ; résout aussi les invasions EN DIRECT
  terminées par le chemin normal (jamais passées par Monban — balayage
  séparé, sinon leur économie ne se déclenchait jamais).
  **Point d'attention découvert en cours de route** : `main()` sortait
  immédiatement si `bot_army_control.enabled=false` (l'état par défaut hors
  session de test) — `driveInvasions` aurait donc été une fonctionnalité
  invisible en production la plupart du temps. Déplacé en tête de `main()`,
  APPELÉ INCONDITIONNELLEMENT avant toute vérification de directive, plus un
  appel supplémentaire à chaque tick de `runBackfill` (le mode par défaut du
  cron planifié). Latence : jusqu'à ~10 min (intervalle du cron) quand
  `enabled=false`, quelques secondes pendant un run actif.
- **Client** : `screen-invasion` (sélecteur de tranche Elo, décision K, via
  RPC `invasion_candidates`) → `invasionAttack()` crée la partie exactement
  comme `createOnlineGame()` (même moteur local) + tague `is_invasion`.
  Popup `#invasion-popup` (`subscribeToInvasions`, realtime sur
  `invasion_requests`) pour le défenseur en ligne, 15s pour accepter.
  `quitOnlineGame()` devient invasion-aware : abandon d'une invasion →
  `invasion_forfeit` (RPC, résolution complète) au lieu du simple update de
  statut d'une partie normale — décision S satisfaite pour le cas explicite
  (bouton "Quitter").
- **Notifications** (I6) : 5 nouveaux types (`invasion_incoming`,
  `invasion_won`, `invasion_lost`, `invasion_defended`, `invasion_repelled`)
  câblés dans l'icône (`openNotificationsModal`) et la pastille du village
  (`villageRefreshBadges`, allowlist Arène étendue). Non cliquables pour
  l'instant (pas de routage dédié) — couleur par défaut du système (cohérent
  avec `challenge`/`tournament_game`).
- **2 bugs de fond trouvés et corrigés PENDANT cette implémentation** (pas
  liés à l'invasion elle-même, mais découverts en creusant `currentUser`) :
  `currentUser` ne porte que `{id, pseudo}` (voir `onlineLoadSession`) — donc
  `monbanRefreshHub()` (V0.96.0) et `pzHandlePlayEnd()` (V0.95.0)
  utilisaient un `currentUser.elo`/`currentUser.elo_Xs` qui n'a **jamais**
  existé, retombant systématiquement sur la valeur par défaut (1200) en
  production. Corrigés : les deux relisent maintenant `profiles.elo_Xs` via
  une requête dédiée, comme le fait déjà `loadAndShowMyElo()`.

### Simplifications V1 assumées (documentées, pas des oublis silencieux)

- **Pas de choix interactif de la monnaie par le vainqueur** (décision I/J
  envisageait un choix) : V1 = toujours automatique, la monnaie la mieux
  fournie du perdant, jamais le Koku. Une UI de choix reste à construire.
- **Pas de fenêtre de reconnexion de 45s** (décision S) : seul le clic
  explicite "Quitter" déclenche un forfait. Une coupure réseau simple ne
  perd pas encore automatiquement — chantier futur (nécessiterait un
  pg_cron ou un suivi de présence dédié).
- **Décision L (exclusion tournoi/guerre de guilde) non implémentée** :
  `invasion_candidates` ne filtre pas encore les joueurs actuellement engagés
  ailleurs.
- ~~Suivi fin des faiblesses de Monban pour les parties en ligne (parité
  complète avec `NT2_PROFILE`) reste un chantier ouvert~~ **Fait le
  2026-08-18 (V0.111.0)** : `monbanComputeWeaknessDeltas`/`monbanDominantWeakness`
  (index.html ~22370) calculent exposition/occasions manquées/passivité sur
  chaque partie en ligne, envoyés à `monban_learn_from_game`. Décision Wurmz
  explicite : Monban est un **clone** du joueur (forces ET défauts reproduits,
  jamais corrigés) — contrairement à NT2 qui EXPLOITE la faiblesse d'un
  adversaire humain, Monban REPRODUIT sa propre faiblesse dominante quand il
  joue à la place du joueur absent. Implémenté côté Edge Function `monban-move`
  uniquement (pas de modification d'`evalTrainer`, équilibre validé le
  2026-07-26 non touché) : avec une probabilité dérivée du taux réel observé
  (plafonnée à 60%), la liste de coups candidats passée à `minimaxPlay` est
  filtrée (occasion manquée → coups gagnants exclus ; passivité → coups qui
  approchent l'Épéiste adverse exclus) ou la profondeur de recherche réduite
  (exposition). Vérifié par harnais Node rejouant le moteur réel extrait
  d'`index.html` (pas seulement par lecture de code) : sur une position avec
  capture disponible, `missedWin` forcé fait effectivement manquer la
  capture ; sur la position initiale, `passivity` forcé réduit le pool de 8
  à 4 coups (exactement les coups qui rapprochaient de l'adversaire) ;
  `exposure` forcé réduit la profondeur de 2. Pas de migration SQL requise
  (`monban_learn_from_game` fait déjà un merge superficiel qui absorbe les
  nouvelles clés du profil).
- **`presenceTier()` ne renvoie toujours pas `'combat'`** (trou identifié
  §1) — non nécessaire dans l'architecture retenue (le 15s d'acceptation
  s'applique uniformément, sans distinguer présence), mais reste un état mort
  si un autre besoin en dépend un jour.

### Reste à faire avant que les modes soient complets

P3 « complet » (tri/filtres/miniature rendue à la volée), P5 (page stats/
notation détaillée, vue créateur), P6 (économie puzzle), P7 (déblocables),
P8 (modération UI — les RPC existent déjà côté SQL) — écran de consultation
de l'historique d'invasions subies/menées, achat de bouclier côté UI (la RPC
`monban_buy_shield` existe, pas de bouton), et les simplifications V1
ci-dessus.

### Objectifs de puzzle — case cible + limite de tours (2026-08-18, V0.113.0)

**Découverte en creusant le retour de Thomas** : le menu « Objectif »
(Éliminer/Survivre N tours/Atteindre une case) était **purement décoratif**
— quel que soit le choix, la seule victoire réellement vérifiée était la
capture standard de l'épéiste adverse. `reach_cell` n'avait même pas de
mécanisme pour poser la case cible (bug confirmé par Thomas).

**Fait** : nouvel outil `🎯 Cible` dans l'éditeur partagé (`lab-ed-widget`,
visible uniquement en contexte Puzzle via `_labEdContext`, jamais dans le
Labo) — `_labEd.targetCell`, rendu sur le plateau. Nouveau champ « Limite de
tours » (optionnel, `objective.maxTurns`), combinable avec `eliminate` OU
`reach_cell` — décision Wurmz : « capturer avant X tours » et « rejoindre la
case avant X tours » sont deux objectifs distincts, tous deux couverts par
ce même champ appliqué à des types différents. `pzBuildObjective()` valide
qu'une case cible existe avant d'enregistrer/tester (sinon un puzzle
publié serait à jamais impossible à réussir). `pzCheckObjective()`, appelée
depuis `switchTurn()` (garde interne, aucun effet hors puzzle), vérifie
l'atteinte de la case et la limite de tours à chaque coup qui n'a pas déjà
gagné par capture standard. Aucune migration SQL : `objective` est déjà une
colonne jsonb, ce sont seulement de nouvelles clés.

**Non fait** : `survive_turns` reste tout aussi décoratif qu'avant (gap
préexistant, hors périmètre de cette passe — pas demandé, pas touché).

**« Plusieurs adversaires » (Thomas)** : vérifié dans le code — l'éditeur
permet déjà de poser autant de pièces Noires que voulu (outil « Poser » +
sélecteur de couleur), et `labValidateFormat` ne limite QUE le nombre
d'épéistes (exactement 1 par camp, hors Champ de bataille). Aucune
restriction technique trouvée → pas de fix appliqué, le blocage réel de
Thomas reste à identifier avec lui (repro exacte ou capture d'écran) avant
de coder quoi que ce soit ici.

### Sumo — les mains poussent, ne tuent plus (2026-08-18, V0.113.0)

Décision Wurmz : en mode sumo, une épée (« main ») qui atteint le Combattant
(épéiste) adverse ne le capture plus directement — elle le POUSSE, sur le
même patron que l'épéiste et le bouclier (déjà existant). Seule l'éjection
hors du plateau (`!isValid(...)`) fait gagner (`pushOut`+`pushCaptures`).
Appliqué globalement partout où `G.sumoMode` est actif (décision confirmée) :
le mode SUMO classé en Arène, ET tout format custom/puzzle avec la case
« Sumo » cochée. Un seul et même réglage différencie Épéiste/Combattant et
Épée/Main (`labEdTypeLabel`, selon `_labEd.sumo`) — pas de piste de pièce
séparée (décision confirmée). Modification dans `legalMoves` (branche
`sword`), zéro changement pour les formats non-sumo (vérifié par harnais
Node sur le moteur réel extrait d'`index.html` : capture directe intacte
hors sumo, poussée simple + éjection = victoire en sumo, poussée d'une
épée adverse inchangée).

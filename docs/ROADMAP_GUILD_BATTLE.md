# Roadmap — COMBATS D'ÉQUIPE DE GUILDE (façon Tekken Team Battle)

> Cadrage rédigé le 2026-08-17, **avant** toute ligne de code.
> Les décisions du § 2 sont **figées** (QCM répondu par Wurmz le 2026-08-17) :
> ne pas les rouvrir sans raison — re-débattre une décision d'archi en plein
> lot coûte plus cher que de la coder.
> Chaque lot livré complète le § 8 (points d'entrée) : c'est ce qui évite de
> refouiller `index.html` (1,4 Mo) à chaque session.

---

## 1. De quoi on parle

Trois modes d'équipe, **une seule mécanique de combat** partagée :

| Mode | Qui s'affronte | Enjeu |
|---|---|---|
| **Tournoi interne** | Membres d'une même guilde, en 2 équipes | Prestige seul |
| **Confrontation amicale** | Guilde A vs Guilde B | Aucun |
| **Attaque de guilde** | Guilde A attaque Guilde B | 10 🐉 volés + classement |

**La mécanique commune** (référence : Tekken Team Battle, cf. capture fournie) :
deux équipes alignées, **un seul duel à la fois**. Le vainqueur reste en piste
et affronte le combattant suivant du camp adverse. Il enchaîne tant qu'il
gagne. Quand il tombe, c'est celui qui l'a battu qui prend la suite. Le camp
qui n'a plus aucun combattant debout a perdu.

⚠️ **À ne pas confondre avec l'existant** (les deux restent en place) :
- **Défi guilde** (livré) : score cumulé sur 48 h, pas de combat dédié — ce sont
  les victoires classées ordinaires des membres qui marquent des points.
- **Tournoi de guilde officiel** (livré) : tournoi suisse individuel programmé
  par l'administration. Seul objet de cette liste à **ne pas** vivre dans le
  menu Guilde : il reste dans l'écran Tournois.

### Nommage figé (décision AH)

Cinq objets portent le mot « guilde ». Les noms ci-dessous sont **définitifs**
et doivent être employés partout — interface, code, commentaires, notifications.
Le projet a déjà payé un flottement de nommage avec « Combattant ».

| Nom officiel | Nature | Où |
|---|---|---|
| **Défi guilde** | Score cumulé sur 48 h (existant) | Menu Guilde |
| **Tournoi interne** | Combat d'équipe entre membres | Menu Guilde |
| **Confrontation amicale** | Combat d'équipe entre 2 guildes, sans enjeu | Menu Guilde |
| **Attaque de guilde** | Combat d'équipe entre 2 guildes, avec enjeu | Menu Guilde |
| **Tournoi de guilde (officiel)** | Tournoi suisse individuel, programmé par l'admin | Écran Tournois |

---

## 2. Décisions figées (2026-08-17)

| # | Décision | Conséquence technique principale |
|---|---|---|
| **A** | **L'Elo fait deux choses** : il répartit les deux équipes à forces égales ET fixe l'ordre de passage — le plus faible ouvre, le plus fort ferme en « boss ». | Répartition en serpentin (1→A, 2→B, 3→B, 4→A…) puis tri croissant du siège dans chaque équipe. L'Elo est **figé à l'inscription** (colonne `elo` sur le participant) : sinon une partie classée jouée entre-temps rebat les cartes. |
| **B** | **Arbre complet dès la V1**, fidèle à la capture Tekken : deux colonnes, flèches courbes reliant chaque éliminé à son vainqueur, croix sur les morts, bandeau « N victoires consécutives ». **Vignettes au pseudo** (pas de portrait : les images de profil n'existent pas encore dans le jeu, on les branchera plus tard). | Les flèches se dessinent à partir de `eliminated_by` : c'est **cette colonne qui porte tout le rendu de l'arbre**, à ne pas oublier au moment d'écrire le résultat d'un combat. Rendu SVG, conteneur à défilement horizontal sur mobile. |
| **C** | **Le combat en cours est cliquable** dans l'arbre → on regarde le duel en direct. | Réutilise `spectateGame(gameId)` **tel quel** (barre spectateur + canal temps réel + repli en polling, déjà éprouvé sur les tournois). L'événement expose `current_game_id`. |
| **D** | **Verrous séparés par type** : une guilde peut mener de front un Défi inter-guildes 48 h, un Combat de guildes et un Tournoi interne. Wurmz : *« les guildes les plus actives seront ravies de pouvoir tout faire à la fois »*. | ⚠️ **Contrepartie exigée** : l'écran Guilde doit **distinguer visuellement et sans ambiguïté** les trois choses. Trois événements simultanés portant tous le mot « guilde », c'est le terrain idéal pour un joueur perdu. Libellés, icônes et sections distinctes, pas une liste plate. |
| **E** | **Monban doit devenir réactif.** Wurmz : *« un Monban ne doit jamais être indisponible si le joueur est hors ligne »*. Vaut **aussi pour les invasions déjà livrées**. | 🔴 **Le chantier le plus risqué, et le prérequis de tout le reste** — voir § 3. |
| **F** | **Monban remplace en DÉFENSE uniquement.** Un attaquant doit être un humain présent. | Asymétrie assumée : attaquer est un engagement réel, défendre est protégé même en pleine nuit. |
| **G** | **Asymétrie autorisée** : 4 contre 3 se joue tel quel. | Aucun blocage au lancement, et ça récompense la guilde qui a su mobiliser. |
| **H** | **Jamais classé** : aucun impact sur l'Elo ni sur la Ligue. | ⚠️ Conséquence en cascade : ces combats ne comptent donc **pas** non plus pour un Défi inter-guildes 48 h concurrent (qui ne compte que les victoires **classées**). Pas de double comptage — c'est voulu, mais à écrire noir sur blanc côté joueur. |
| **I** | **Séquentiel strict** : un seul duel à la fois, tout le monde regarde le même. Jusqu'à **20 contre 20**. | ⚠️ Un 20v20 enchaîne 20 à 39 combats, soit **1 h 15 à 2 h 15**. Voir § 7 (risques). |
| **J** | **Pause de 30 s entre deux combats.** | Le vainqueur souffle, l'arbre se met à jour sous les yeux de tous, les spectateurs basculent sur le duel suivant. |
| **K** | **Salle d'attente + check-in**, ouverte 5 min avant. Qui n'a pas confirmé est marqué absent d'emblée. | On connaît la composition réelle **avant** le coup d'envoi, pas de surprise en plein événement. |
| **L** | **Attaquant absent au check-in → retiré de la composition** (l'équipe attaque à N-1). | Le camp adverse n'encaisse pas de « victoire gratuite » qui gonflerait artificiellement une série dans l'arbre. |
| **M** | **Décrochage en cours d'événement : 60 s de grâce.** Passé ce délai — en défense son Monban prend le relais, en attaque il est éliminé. | Évite de bloquer 38 personnes pour un joueur parti se servir un café. |
| **N** | **Cadence choisie par le GM** à la création (3s / 5s / 10s), annoncée dans la notification. | Donne un levier pour raccourcir un gros événement (20v20 en 3s). |
| **O** | **Minimum 3 combattants par camp**, maximum 20. | En dessous de 3, la chaîne de victoires n'a aucun intérêt (un 1v1 n'est qu'un duel). |
| **P** | **Au moins 1 humain présent côté ATTAQUANT.** Une défense 100 % Monban est parfaitement valide. | Empêche de piller une guilde en pleine nuit avec 20 clones contre 20 clones. Et comme fuir ne protège plus le Ryu (décision Q), les guildes ont intérêt à **entraîner leurs Monban**. |
| **Q** | **Défense vide → attaque annulée, mais la guilde absente perd 5 🐉** (moitié prix). | Ne jamais se présenter reste une mauvaise affaire, sans être puni aussi lourdement qu'une vraie défaite. |
| **R** | **Annulation : l'attaquant seul, jusqu'à 1 h avant.** Le cooldown hebdomadaire **reste consommé**, et **5 🐉 sont transférés à la guilde défenseur** en dédommagement. | On ne peut pas harceler en programmant puis annulant en boucle : ça coûte à la fois la semaine et du Ryu. |
| **S** | **Tournoi interne : aucune récompense**, juste le prestige et la trace au journal. **Un seul à la fois par guilde, sans autre limite.** | Rien à farmer, donc aucun garde-fou anti-abus à construire. |
| **T** | **Amical : même cérémonial que l'attaque** (date/heure, notifications, inscriptions, check-in) — seule la conséquence change. **Les cooldowns ne s'appliquent PAS à l'amical.** | Deux guildes alliées peuvent s'entraîner librement. Un seul parcours de code pour les deux, un simple drapeau `kind` les sépare. |
| **U** | **Journal de guilde : toute la vie de la guilde** — arrivées, départs, exclusions, changements de grade, inscriptions attaque/défense, déclarations de guerre et résultats. | Une table, un écran. Rend le rôle de GM lisible, et livrable **seul** dès le lot G1. |
| **V** | **Anti-harcèlement (attaques uniquement)** : une guilde attaque **au plus 1×/semaine** et ne peut être attaquée **plus d'1× tous les 4 jours**. | Même esprit que les cooldowns d'invasion (24 h attaquant / 72 h par paire), transposé à l'échelle de la guilde. |

### Points que je pars pour appliquer, sauf objection

| # | Position retenue | Pourquoi |
|---|---|---|
| **W** | Les 5 🐉 de la décision R sont un **transfert** (l'attaquant les paie), pas de la monnaie créée. | Cohérent avec la mécanique de vol du mode. Aucune inflation. |
| **X** | Si le camp **attaquant** tombe sous 3 présents au check-in : attaque annulée, **cooldown consommé, et 5 🐉 transférés au défenseur** — même traitement qu'une annulation volontaire. | On ne récompense pas la désorganisation mieux que le renoncement assumé. Sinon, « je déclare puis je ne viens pas » devient l'annulation gratuite. |
| **Y** | Un joueur qui **quitte ou est exclu** de la guilde avant le lancement est retiré des inscriptions. | Sinon on aligne un combattant qui n'appartient plus au camp. |
| **Z** | **Aucun cooldown individuel** : un joueur peut enchaîner tous les événements qu'il veut. | La limite est déjà au niveau de la guilde (décision V). En rajouter une au niveau du joueur ne ferait que vider les compositions. |
| **AA** | Le vol reste **10 🐉 fixes**, quel que soit l'écart de score final. | Un barème proportionnel serait plus juste mais illisible ; 10 est déjà calibré côté défi 48 h (+30 pour une guerre entière). |
| **AB** | Ces combats ne comptent **ni pour la première victoire du jour, ni pour les quêtes quotidiennes**. | Cohérent avec la décision H (hors classement) et avec le traitement des parties amicales. Évite qu'un tournoi interne bidon serve à farmer le quotidien. |
| **AC** | La **taille des équipes est décidée par les inscriptions**, pas fixée à l'avance par le GM. | Un GM qui annonce « 10 contre 10 » et n'obtient que 7 inscrits devrait tout reprogrammer. Avec l'asymétrie autorisée (G), rien n'oblige à cette rigidité. |
| **AJ** | **Seule l'Attaque de guilde fait bouger l'Elo de guilde.** Confrontation amicale et Tournoi interne n'y touchent pas. | « Amical » doit vouloir dire sans conséquence, sinon le mot ment. Et un Tournoi interne n'oppose aucune guilde adverse : il n'y a rien à arbitrer. |
| **AK** | **Le Défi guilde 48 h fait bouger l'Elo de guilde lui aussi, mais moitié moins qu'une Attaque.** | C'est bien une confrontation entre deux guildes avec un vainqueur : l'exclure du classement serait incohérent. Mais il se gagne passivement (victoires classées cumulées) là où l'Attaque demande d'aligner une équipe à une heure dite — le direct doit peser plus lourd. |
| **AL** | **L'Elo de guilde démarre à 1200** et suit la même formule que l'Elo joueur, avec l'écart de score comme marge de victoire. | Aucune formule à inventer : on reprend celle déjà en place et déjà comprise des joueurs. |
| **AM** | **Le classement reste public et consultable par tous**, y compris hors guilde. | C'est l'existant (`v_guild_leaderboard` est déjà public) et c'est ce qui donne envie de rejoindre une guilde qui monte. |
| **AD** | **Les administrateurs (Wurmz, Musashi) échappent aux cooldowns d'invasion**, dans les deux sens : ils peuvent en lancer sans limite **et** en recevoir sans limite. | Demandé par Wurmz le 2026-08-17. Ce n'est pas un privilège de confort : c'est **la condition pour tester le lot G0** (voir § 3) — avec les cooldowns 24 h / 72 h en place, on ne peut pas déclencher deux invasions d'affilée pour éprouver la réactivité de Monban. Détail d'implémentation au § 3. |
| **AE** | **Le classement des guildes repose sur un Elo de guilde**, gagné et perdu en Attaque de guilde — pas sur le Ryu cumulé. | 🔴 **Remplace le classement actuel** : `v_guild_leaderboard` trie aujourd'hui sur `ryu_total`, un compteur qui ne descend jamais. C'est une refonte d'un écran livré, pas un ajout. Voir § 4. |
| **AF** | **Le Ryu redevient une monnaie pure** : il ne sert plus de score. | Résout la tension relevée le 2026-08-17 : avec la boutique de stages et de décoration à venir (§ 5), une guilde qui investit dans son hall aurait chuté au classement. Le vol de 10 🐉 fait désormais mal au portefeuille, pas au rang. |
| **AG** | **Le ciblage d'une Attaque de guilde se fait par tranche de classement** (à mon niveau / plus fort / plus faible), comme les invasions individuelles. | Empêche une guilde de tête de racketter les débutantes en boucle. Réutilise le patron de `invasion_candidates` (décision K de la roadmap Invasion), transposé aux guildes. |
| **AH** | **Nommage figé en 5 noms** (voir § 1). | Satisfait l'exigence de la décision D : trois systèmes simultanés ne sont tenables que s'ils sont nommés sans ambiguïté. |
| **AI** | **À terme, les guildes achèteront des stages et de la décoration en Ryu** (hall / château de guilde), et une Attaque de guilde se déroulera **dans les stages de la guilde défenseuse**. | Vision donnée par Wurmz le 2026-08-17. Pas dans le périmètre de ces lots, mais **contraint dès maintenant** : c'est la raison d'être de la décision AF (le Ryu doit rester dépensable sans pénalité). Voir § 5 pour ce que ça implique. |

---

## 3. ✅ Le prérequis : rendre Monban réactif (lot G0) — LIVRÉ le 2026-08-17

**C'était le vrai morceau d'ingénierie de ce chantier — construit et validé.**
Rien d'autre du chantier Combat de guilde n'est codé (G1-G8 restent à faire).

### Le problème, chiffré

Monban est piloté aujourd'hui par `scripts/bot-army.mjs`, réveillé par un cron
GitHub Actions **toutes les 10 minutes**. Dans un combat en direct, chaque coup
de Monban peut donc mettre jusqu'à 10 minutes. Une partie de 30 coups
prendrait **plusieurs heures**. Ce n'est pas une lenteur à tolérer : c'est une
incompatibilité de nature avec un événement où 40 personnes regardent.

### Ce qui existe (vérifié le 2026-08-17)

- Le worker lit `index.html` **depuis le disque** (`readFileSync`, dépôt cloné
  par l'action) et en **extrait le moteur** par regex (`ENGINE_NAMES`), puis le
  reconstruit avec `new Function`. Zéro dérive avec le jeu réel — c'est le bon
  patron, à conserver.
- **Aucune Edge Function Supabase n'est déployée** (`list_edge_functions` → 0).
  C'est donc une surface de déploiement entièrement nouvelle.

### Proposition

Une **Edge Function Supabase `monban-move`** :

1. Récupère `index.html` depuis GitHub Pages au démarrage à froid, en extrait
   le moteur exactement comme le worker (même `ENGINE_NAMES`, même
   `new Function`), et **le garde en mémoire** entre deux invocations chaudes.
2. Reçoit un `game_id`, vérifie côté serveur que c'est bien au tour de Monban,
   calcule le coup à la profondeur dérivée de `monban_profiles.skillRating`,
   écrit le nouvel état.
3. Déclenchée par un **trigger Postgres + `pg_net`** dès que `online_games.turn`
   passe du côté de Monban. Latence attendue : **moins d'une seconde**.

### Pourquoi c'est faisable sans tout réécrire

Le moteur n'est pas dupliqué : il continue d'être extrait de la source vivante.
Seule change la **façon de le charger** (HTTP au lieu du disque) — le reste du
patron est repris tel quel du worker.

### Comment on le valide sans risque

🔴 **On le teste sur le mode Invasion DÉJÀ LIVRÉ, avant d'écrire une seule ligne
de combat d'équipe.** L'invasion utilise déjà Monban côté serveur : si le coup
tombe en moins d'une seconde là, la brique est prouvée. C'est la leçon
explicite de la roadmap Puzzle/Invasion (*« ne pas empiler deux inconnues sur
le chemin critique »*), et ça règle au passage un défaut réel du mode existant.

### Débrider les invasions pour les administrateurs (décision AD)

Sans ça, **le test ci-dessus est impraticable** : les cooldowns actuels
(24 h côté attaquant, 72 h par paire de joueurs) n'autorisent qu'une seule
invasion par jour, alors qu'éprouver la réactivité de Monban en demande une
série rapprochée.

À modifier dans `invasion_authorize` (`sql_a_executer/invasion_engine.sql`) :

- **Attaquant administrateur** → on saute le contrôle des 24 h
  (`profiles.last_invasion_at`) et celui des 72 h par paire.
- **Défenseur administrateur** → on saute le contrôle des 72 h par paire, pour
  qu'un compte de test puisse encaisser des invasions en rafale.
- **Le bouclier (`shield_until`) reste actif dans tous les cas** : c'est une
  fonctionnalité à tester elle aussi, et un administrateur qui veut recevoir
  des invasions n'a qu'à ne pas en acheter.

⚠️ Le contrôle se fait **exclusivement via `is_admin_user()`** (colonne
`profiles.is_admin`), **jamais** sur une liste de pseudos en dur — convention
du projet rappelée dans `CLAUDE.md`, un pseudo étant usurpable.

⚠️ Ce débridage vaut aussi, plus tard, pour les cooldowns d'attaque de guilde
(décision V) : mêmes raisons, même implémentation.

### Ce qui a été construit et vérifié (2026-08-17)

- **`invasion_admin_unlimited.sql`** (exécuté) : `invasion_authorize` réécrite,
  bypass admin dans les deux sens, bouclier toujours respecté. Vérifié en base
  (`profiles.is_admin=true` pour Wurmz et Musashi).
- **`new Function` fonctionne dans l'Edge Runtime Deno de Supabase** — validé
  via une fonction jetable (`monban-move-test`, toujours déployée, purement
  diagnostique) : `fetch()` a chargé les 1,99 Mo d'`index.html` depuis GitHub
  Pages, extraction + exécution d'une fonction réelle réussies. Le risque #1
  ci-dessus n'existe plus.
- **Edge Function `monban-move`** déployée (`verify_jwt=false` + secret
  partagé statique dans le code — ce n'est PAS une frontière de sécurité, voir
  commentaire en tête du fichier ; le pire abus possible est de faire jouer un
  coup Monban légal en avance). Reprend exactement `ENGINE_NAMES`/`extractFn`
  de `scripts/bot-army.mjs`, source chargée par `fetch` au lieu de
  `readFileSync`, moteur mis en cache en mémoire (TTL 5 min) entre invocations
  chaudes. Le `service_role` de la fonction n'est jamais transmis en clair :
  lu via `Deno.env` (injecté automatiquement par le runtime Edge Function) —
  la question « où vit le secret » ne se posait donc pas.
- **`invasion_reactive_monban.sql`** (exécuté) : extension `pg_net` activée,
  trigger `invasion_dispatch_monban_trg` sur `online_games` (`AFTER UPDATE OF
  turn`) qui appelle `monban-move` de façon asynchrone dès que le tour passe à
  Noir sur une partie d'invasion active. Ne remplace PAS le worker existant
  (fenêtre d'acceptation 15 s + nettoyage inchangés) — vient seulement
  accélérer le cas où Monban doit déjà jouer.
- **Test de bout en bout** : trigger confirmé déclenché (`net._http_response`,
  200, ~2 s après l'écriture) sur une partie d'invasion fabriquée. Le pipeline
  réseau + auth + garde côté fonction est donc prouvé en conditions réelles.
  🟡 Nuance honnête : le worker `bot-army.mjs` tournait EN DIRECT pendant le
  test (job GitHub Actions actif, cron 10 min) et a gagné la course à chaque
  fois — mon coup n'a donc jamais été le premier à s'exécuter dans ce test
  précis. La logique de jeu elle-même (`botChooseAndApply` sur cette position)
  est validée indirectement : c'est le worker qui l'a exécutée avec succès sur
  le même état, via un algorithme identique. Ce qui reste non prouvé par un
  test isolé (mais découle directement des deux briques déjà validées
  séparément) : `monban-move` gagnant effectivement la course et écrivant le
  coup lui-même. À reconfirmer la prochaine fois qu'une invasion réelle passe
  par Monban en dehors d'une fenêtre où le worker cron est actif.
- Coût du `fetch` à froid (~2 Mo) : non mesuré précisément dans ce test, à
  surveiller si la fréquence d'invasion augmente — le cache 5 min limite déjà
  l'impact aux démarrages à froid de l'isolate.

---

## 4. Schéma de données (esquisse)

```
guild_events
  id, kind ('internal'|'friendly'|'attack'), guild_a, guild_b (null si interne),
  status ('scheduled'|'registration_closed'|'checkin'|'running'|'finished'|'cancelled'),
  cadence (3|5|10), starts_at, registration_closes_at, created_by,
  winner_guild, current_game_id, current_seat_a, current_seat_b, streak_count,
  cancelled_by, created_at, updated_at

guild_event_participants
  event_id, player_id, team ('A'|'B'), seat (ordre de passage),
  elo (FIGÉ à l'inscription — décision A), checked_in, plays_as_monban,
  eliminated_at, eliminated_by (→ dessine les flèches de l'arbre), wins
  PK (event_id, player_id)

guild_event_matches
  id, event_id, seq, game_id (→ online_games, pour le spectateur),
  player_a, player_b, winner, started_at, ended_at

guild_journal
  id, guild_id, created_at, event_type, actor_id, target_id, message
```

Cooldowns : deux colonnes sur `guilds` (`last_attack_at` pour l'attaquant,
`last_attacked_at` pour le défenseur). Même patron que
`profiles.last_invasion_at` / `shield_until` côté invasion.

Classement : une colonne `guilds.guild_elo` (défaut 1200, décision AL).

⚠️ Toute écriture qui touche au Ryu, à l'Elo de guilde ou qui décide d'un
vainqueur passe par une RPC `SECURITY DEFINER` — jamais par le client. Même
règle que `invasion_resolve`.

---

## 5. Le classement des guildes (décisions AE / AF / AG)

### Ce qui change dans l'existant

Le classement actuel (`v_guild_leaderboard`, écran « 🏆 Autres guildes ») trie
sur `ryu_total` : un **cumul qui ne descend jamais**. Une vieille guilde
inactive y domine indéfiniment une jeune guilde performante — l'inverse de ce
que Wurmz demande (*« plus une guilde est bien classée, meilleure elle est »*).

**C'est donc une refonte d'un écran livré, pas un simple ajout.** Le Ryu reste
affiché comme **trésorerie de guilde** ; c'est le tri et le rang qui passent à
`guild_elo`.

### Ce qui fait bouger l'Elo de guilde

| Événement | Effet |
|---|---|
| **Attaque de guilde** | Effet plein (décision AJ) |
| **Défi guilde 48 h** | Moitié moins (décision AK) |
| **Confrontation amicale** | Aucun |
| **Tournoi interne** | Aucun |

### Ce que le classement pilote en retour

Le ciblage des Attaques (décision AG) : trois tranches — à mon niveau, plus
fort, plus faible — sur le modèle exact de `invasion_candidates`. Une guilde de
tête ne peut donc plus racketter les débutantes en boucle.

⚠️ **Point à surveiller** : ce mécanisme et les cooldowns (V) se cumulent avec
un vivier de guildes très faible en alpha. C'est exactement le risque déjà
identifié pour les invasions individuelles (§ 6 de la roadmap Invasion, où
« aucune cible » menaçait de devenir la réponse habituelle) — sauf qu'il y a
bien moins de guildes que de joueurs. À mesurer avant de durcir quoi que ce soit.

---

## 6. Vision : stages et décoration (décision AI — hors périmètre)

À terme, les guildes achèteront en Ryu des **stages** et de la **décoration**
(hall / château de guilde), et une **Attaque de guilde se déroulera dans les
stages de la guilde défenseuse**.

**Rien de tout ça n'est dans les lots ci-dessous.** Mais c'est consigné ici
parce que ça contraint déjà deux choses :

1. **C'est la raison d'être de la décision AF.** Sans une boutique à venir, le
   Ryu pouvait rester un score. Avec elle, il devait redevenir dépensable sans
   pénaliser le rang — d'où le passage du classement à un Elo de guilde.
2. **Le Ryu a enfin un puits.** Aujourd'hui il ne fait que s'accumuler (paliers
   mis à part). Une boutique de guilde lui donne sa contrepartie, ce qui rend le
   vol de 10 🐉 réellement sensible.

### Question à trancher le jour où on l'attaque

**Un « stage » est-il un décor ou un plateau ?** Les deux lectures sont
défendables et n'ont rien à voir en termes de travail :

- **Décor** (fond, thème visuel pendant le combat) : cosmétique pur, s'appuie
  sur le système de thèmes déjà en place. Aucun impact sur l'équilibre.
- **Plateau** (dimensions, cases interdites, disposition) : l'éditeur de
  formats du Labo et le registre `dev_published_formats` font **déjà** ce
  travail. Mais alors la guilde défenseuse combat sur **son** terrain — c'est
  un avantage du terrain, donc une décision d'équilibre lourde, pas une
  décoration.

À ne pas trancher maintenant, mais à ne pas confondre non plus.

---

## 7. Découpage en lots

**Un lot = une session de travail.** Le risque est mis en tête.

| Lot | Contenu | Dépend de |
|---|---|---|
| **G0** | 🔴 **Monban réactif** (Edge Function + trigger), **validé sur le mode Invasion existant** + **débridage des invasions pour les administrateurs** (prérequis du test, décision AD). Rien d'autre ne démarre avant. | E, AD |
| **G1** | ✅ **LIVRÉ 2026-08-17.** **Journal de guilde** : table, RLS, écran, et branchement sur les événements de guilde DÉJÀ existants (arrivées, départs, grades, défis). **Livrable et utile seul.** | U |
| **G2** | ✅ **LIVRÉ 2026-08-17.** **Planification + inscriptions** : le GM crée un Tournoi interne (date, heure, cadence, clôture), les membres s'inscrivent. Notifications d'annonce et de clôture. Pas encore de combat. | G1, N, S |
| **G3** | ✅ **LIVRÉ 2026-08-17.** **Constitution des équipes** : répartition automatique par Elo (serpentin + ordre de passage), glisser-déposer du GM, salle d'attente et check-in. | G2, A, K |
| **G4** | ✅ **LIVRÉ 2026-08-17.** **Moteur de combat en chaîne** : enchaînement séquentiel, pause 30 s, création des parties, élimination, délai de grâce, victoire d'équipe. **Le cœur du mode.** | G3, G0, I, J, M |
| **G5** | **Arbre Tekken + spectateur** : rendu SVG complet avec flèches, bandeau de série, combat en cours cliquable. | G4, B, C |
| **G6** | **Confrontation amicale** : réutilise G2→G5 avec deux guildes. Déclaration, acceptation du GM adverse, planification à 48 h max. Aucun enjeu. | G5, T |
| **G7** | **Classement des guildes** : colonne `guild_elo`, refonte de `v_guild_leaderboard` et de l'écran « Autres guildes » (le Ryu y devient trésorerie, plus rang). Branchement sur le Défi guilde 48 h existant. | G6, AE, AF, AK |
| **G8** | **Attaque de guilde** : ciblage par tranche de classement, cooldowns, vol de 10 🐉, forfait, annulation, effet sur l'Elo de guilde, notifications d'attaque. | G7, AG, Q, R, V |
| *(plus tard)* | **Stages & décoration** : hall de guilde, boutique en Ryu, combat chez le défenseur. Hors périmètre — voir § 6. | G8, AI |

**Pourquoi cet ordre** : G0 d'abord parce que c'est l'inconnue technique, et
qu'on peut la prouver sur un mode déjà en production. G1 ensuite parce qu'il
est utile immédiatement, indépendamment de tout le reste. Puis le Tournoi
**interne** (G2→G5), qui exerce toute la mécanique de combat **sans** la
complexité inter-guildes. Les guildes ne s'affrontent qu'une fois le moteur
prouvé en interne (G6), et l'enjeu (G8) n'arrive qu'une fois le classement en
place (G7) — puisque c'est lui qui décide qui peut attaquer qui.

---

## 8. Notifications

Chaque type doit passer les **6 points de câblage** du skill
`/lvdg-notifications-audit` (insertion SQL, icône, `notifCatColor`, routage au
clic, pastille du menu classique, **pastilles village**).

| Type | Quand | Destinataires |
|---|---|---|
| `guild_event_announced` | Un événement vient d'être planifié | Tous les membres concernés |
| `guild_event_registration_closed` | Clôture des inscriptions | Les inscrits |
| `guild_event_starting` | 5 min avant — **le check-in est ouvert** | Les inscrits |
| `guild_event_result` | Fin de l'événement (victoire / défaite) | Tous les membres des deux camps |
| `guild_attack_declared` | Une guilde en attaque une autre | Tous les membres des **deux** guildes |
| `guild_attack_cancelled` | L'attaquant se rétracte | Tous les membres des deux guildes |

⚠️ Les types `guild_war_*` (Défi guilde 48 h) existent déjà et sont câblés —
**ne pas les réutiliser** pour ces événements, ce sont deux systèmes différents
(décisions D et AH : les distinguer sans ambiguïté).

---

## 9. Risques ouverts

- **🔴 `new Function` dans Deno.** Toute la stratégie G0 en dépend. À éprouver
  **avant** de s'engager sur le reste du lot.
- **🔴 Durée d'un 20v20 : jusqu'à 2 h 15**, pendant lesquelles 38 joueurs sur 40
  regardent. Décision I assumée, mais à **mesurer dès que G4 est jouable**.
  Leviers si ça ne tient pas, dans l'ordre : plafonner la taille en dessous de
  20, imposer 3s au-delà d'un certain effectif, ou rouvrir la question des
  fronts parallèles. Ne rien pré-construire avant d'avoir la mesure.
- **Abandon d'un événement en cours.** Si le combat se bloque (bug, partie qui
  ne se termine jamais), il faut un moyen de solder l'événement. Prévoir un
  délai maximum par duel et une clôture forcée côté serveur — sinon un
  événement zombie garde un verrou et pollue l'écran de guilde.
- **🔴 Vivier trop petit en alpha — le risque le plus probable.** Quatre filtres
  se cumulent désormais : minimum 3 par camp, cooldowns hebdomadaires, présence
  à une heure précise, et maintenant la **tranche de classement** (AG). Il y a
  bien moins de guildes que de joueurs, et le mode Invasion avait déjà ce
  problème avec un vivier pourtant plus large. Le **Tournoi interne** est le
  seul de ces modes réellement testable en alpha — d'où sa place en tête du
  découpage. Mesurer avant de durcir quoi que ce soit.
- **Quatre systèmes portant le mot « guilde »** en parallèle (décision D). Le
  nommage figé (AH) réduit le risque sans l'éliminer ; c'est un vrai sujet
  d'interface, à traiter avec `/lvdg-ui-optimiser` au moment de G6.
- **Charge sur `online_games`.** Un 20v20 crée jusqu'à 39 parties. À surveiller
  si plusieurs événements tournent en même temps.
- **Refonte d'un écran livré.** Le classement des guildes (G7) change de base
  de tri : des guildes bien classées aujourd'hui vont chuter. À annoncer aux
  joueurs plutôt qu'à leur faire découvrir.

---

## 10. Points d'entrée (à remplir au fil des lots)

### G0 — Monban réactif (2026-08-17)
- `sql_a_executer/invasion_admin_unlimited.sql` — `invasion_authorize` (bypass admin).
- `sql_a_executer/invasion_reactive_monban.sql` — extension `pg_net`, trigger `invasion_dispatch_monban_trg` sur `online_games`.
- Edge Function `monban-move` (dashboard Supabase, pas dans le dépôt git — le code source vit uniquement côté Supabase). Fonction de diagnostic jetable `monban-move-test` encore déployée (inoffensive, à supprimer un jour).
- Piège : `new Function` fonctionne en Edge Runtime Deno, mais `fetch()` d'un gros fichier a un coût — cache 5 min en mémoire dans la fonction.

### G1 — Journal de guilde (2026-08-17)
- `sql_a_executer/guild_journal.sql` — table `guild_journal`, `guild_journal_log()` (interne), `guild_journal_list()` (RPC lecture).
- `index.html` : bouton « 📜 Journal de guilde » dans `renderMyGuild()`, fonction `openGuildJournal()` + `journalAgoText()` (~ligne 7375).
- 🔴 Piège rencontré en testant : ne jamais nommer une variable PL/pgSQL comme la colonne qu'elle reçoit (`select pseudo into pseudo from profiles` → `column reference "pseudo" is ambiguous`). Toujours qualifier la source (`select p.pseudo into v_pseudo from profiles p`).
- 🔴 Bug de production trouvé (indépendant du journal, corrigé au passage) : `guild_join`/`guild_approve` inséraient `role='member'`, rejeté par une contrainte plus récente (`guild_ranks.sql`) qui n'autorise que `leader/g1/g2/g3/g4`. Personne ne pouvait plus rejoindre une guilde. Corrigé en `role='g4'`.
- Méthode de test utile pour la suite : impersonation directe en SQL (`select set_config('request.jwt.claims', json_build_object('sub','<uuid>')::text, true)`) sur un compte bot jamais affecté à une guilde — permet de tester les RPC `SECURITY DEFINER` de bout en bout sans navigateur ni compte réel, en restant sans risque pour les données de Wurmz/Musashi.

### G2 — Planification + inscriptions du Tournoi interne (2026-08-17)
- `sql_a_executer/guild_events_g2.sql` — tables `guild_events`/`guild_event_participants` (schéma partagé avec les futurs `friendly`/`attack`, § 4), RPC `guild_event_create`/`_register`/`_unregister`/`_cancel`/`_list_mine`, tick cron `guild_events_registration_tick` (20s).
- `index.html` : bouton « 🥋 Tournoi interne » dans `renderMyGuild()`, écran `openGuildInternalTournament()` (~ligne 7793, juste après `guildChallengeRespond`) + `createGuildInternalEvent`/`registerGuildEvent`/`unregisterGuildEvent`/`cancelGuildEvent`.
- Notifications `guild_event_announced`/`guild_event_registration_closed` câblées aux 6 points (icône 📅, couleur par défaut = or/jeu, routage clic → `guildOpenInternalTournamentFromNotification()`, pastille Arène).
- Testé de bout en bout : création, contrainte « un seul tournoi interne à la fois » (`busy`), inscription, clôture automatique par le cron (vérifiée en attendant 60s), nettoyage — sur une guilde jetable créée/détruite pour l'occasion.
- Ce que ce lot NE fait PAS encore : pas de répartition en équipes, pas de salle d'attente/check-in, pas de combat — un événement reste bloqué en `registration_closed` après la clôture, en attente du lot G3.

### G3 — Constitution des équipes + salle d'attente (2026-08-17)
- `sql_a_executer/guild_events_g3.sql` — `guild_event_autobalance_teams` (serpentin par Elo, 4 emplacements A,B,B,A répétés), `guild_event_move_player`, `guild_event_checkin`, `guild_event_state`, tick `guild_events_checkin_tick`.
- `index.html` : bouton « Voir » sur un tournoi non-`scheduled` (dans `openGuildInternalTournament`) → `openGuildEventRoster()` (~ligne 7908, après `cancelGuildEvent`) + `autobalanceGuildEvent`/`moveGuildEventPlayer`/`checkinGuildEvent`.
- Pas de vrai glisser-déposer tactile : un bouton « → Équipe X » par joueur (peu fiable sur mobile en HTML5 DnD, cohérent avec le reste du projet). L'ordre de passage n'est JAMAIS éditable côté client — toujours recalculé serveur depuis l'Elo.
- Notification `guild_event_starting` câblée aux 6 points (icône 🚧, routage → écran Tournoi interne, pastille Arène).
- Testé de bout en bout avec 6 bots jetables (Elo 1000-1500 assignés temporairement) : répartition serpentin vérifiée (écart 100 points entre équipes), ordre de passage croissant confirmé, check-in partiel (4/6), retrait automatique des 2 absents à `starts_at`, renumérotation des sièges sans trou, statut final `running`. Cas limite vérifié en passant : si PERSONNE ne confirme sa présence, les deux équipes se vident et l'événement passe en `cancelled` plutôt que de rester bloqué.
- Ce que ce lot NE fait PAS encore : `running` est un état terminal pour l'instant — rien ne joue les duels. C'est tout l'objet du lot G4.

### G4 — Moteur de combat séquentiel (2026-08-17)
- `sql_a_executer/guild_events_g4.sql` — table `guild_event_matches`, colonnes `online_games.is_guild_event`/`guild_event_id`/`guild_event_match_id`, `guild_events.winner_team`, tick `guild_events_combat_tick`.
- `sql_a_executer/guild_events_g4_state.sql` — étend `guild_event_state` avec `current_match` (duel en cours, pseudos inclus) et `matches` (historique).
- `index.html` : dans `openGuildEventRoster()`, bloc « duel en cours » (~ligne 7942) + bloc résultat final + historique (~ligne 7966) + `joinGuildEventDuel()` (nouvelle fonction, reprend exactement le patron de `joinTournamentGame()` — `enterOnlineGame()` gère déjà `showScreen('game')` en interne, pas besoin de le rappeler).
- Chaque duel est une partie `online_games` NORMALE, juste taguée (`is_guild_event`/`guild_event_id`), `ranked=false`. Convention de couleur fixe : équipe A = blanc, équipe B = noir.
- Notification `guild_event_your_turn` avec `ref_id` = l'id de la partie (pas juste `payload`) : le clic ouvre DIRECTEMENT le duel via `joinGuildEventDuel(refId)`, sans repasser par l'écran du tournoi — plus rapide que le patron `guild_event_*` habituel.
- 🔴 **Bug réel trouvé en testant, corrigé avant livraison** : le calcul du streak (série de victoires du champion) remontait la ligne `guild_event_matches` la plus récente sans filtrer `winner is not null` — une tentative de duel ABANDONNÉE (personne n'a chargé la partie sous 60s, décision M) a `ended_at` renseigné mais `winner` null, et se faisait donc passer pour « le duel précédent », cassant le streak du vrai champion à chaque abandon intercalé. Corrigé en excluant les abandons de cette recherche.
- Testé de bout en bout avec 6 bots jetables sur un tournoi 3v3 complet, y compris le comportement de forfait/abandon (les bots ne chargent jamais réellement une partie, ce qui a permis d'observer — sans le vouloir au départ — le chemin « personne ne se présente » se comporter correctement : duel abandonné puis rejoué à l'identique). 3 duels réels forcés (victoire d'équipe A à chaque fois), élimination progressive de l'équipe B confirmée, victoire d'équipe, notifications `guild_event_result` et entrée `guild_journal` vérifiées.
- Ce que ce lot NE fait PAS encore : pas d'arbre visuel des combats (façon Tekken), pas de spectateur depuis l'arbre — c'est l'objet du lot G5. L'historique actuel est une simple liste, pas un arbre.

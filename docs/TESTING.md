# Tests & bug en cours — AXE 1

---

# 🟢 BUG RÉSOLU (corrigé, pas encore re-testé en conditions réelles) : les tournois ne lancent pas la partie

**Correctif appliqué le 2026-07-13, à confirmer par un test à 2 comptes.**

## Symptôme observé (test réel, 2 comptes : PC + téléphone)

Les deux joueurs cliquent « ⚔ Jouer la partie ». L'écran de jeu s'ouvre mais
**le plateau est vide**, avec le message « En attente de l'adversaire… ».
La partie ne démarre jamais.

## Pourquoi le plateau est vide

Ce n'est **pas** un bug d'affichage. `enterOnlineGame()` masque volontairement
le plateau (`classList.add('board-hidden')`) jusqu'à ce que **les deux joueurs
se signalent prêts** — c'est un garde-fou existant pour qu'un joueur ne perde
pas au temps pendant que l'autre charge encore.

La poignée de main :
- `markReadyAndWaitForOpponent(gameId)` → écrit `ready_white` ou `ready_black`
  sur `online_games`, puis sonde l'autre colonne toutes les 500 ms.
- Quand les deux sont vrais → `beginOnlineMatchStart()` → décompte, plateau
  affiché, minuteur lancé.

**Le plateau reste masqué ⇒ la poignée de main n'aboutit pas ⇒ les deux joueurs
ne sont probablement pas dans la MÊME partie.**

## Historique des causes trouvées et corrigées

Chaque correction a fait avancer, sans résoudre entièrement.

### 1. Aucune partie n'était lancée du tout
Les tournois appariaient les joueurs et attendaient une **saisie manuelle** du
résultat (boutons Gagné/Nulle/Perdu). Aucun combat réel.
→ `tournaments_v3.sql` : bouton « Jouer la partie », `startTournamentGame()`,
`joinTournamentGame()`, report automatique du résultat depuis `endGame()`.

### 2. Mauvaise variable d'identifiant de partie
`enterOnlineGame()` stocke l'id dans **`currentOnlineGameId`**, pas dans
`G.onlineGameId` — cette dernière n'est **jamais assignée** dans tout le
fichier (uniquement remise à `null`). L'attachement ne se faisait donc jamais.
→ Corrigé : on utilise `currentOnlineGameId` partout.

### 3. Les DEUX joueurs créaient une partie
Chacun cliquait « Jouer », chacun créait sa propre `online_games`, chacun
attendait l'autre dans **son** plateau. Blocage mutuel.
→ `tournaments_claim.sql` : `tournament_claim_creation(pairing_id)` avec
`FOR UPDATE`, qui attribue un rôle unique : `create` / `join` / `wait`.
Le client `waitForTournamentGame()` sonde et rejoint dès que la partie existe ;
il libère la réservation au bout de ~15 s si le créateur décroche.

### 4. La notification faisait échouer l'attachement
`tournament_attach_game()` insérait une notification **dans la même
transaction**. Si l'insert échouait (contrainte sur `type`, colonne absente…),
**toute la fonction échouait** → la partie n'était jamais rattachée à
l'appariement → l'adversaire ne la trouvait pas et créait la sienne.
→ `tournaments_attach_fix.sql` : l'attachement est fait **en premier**, la
notification est isolée dans un bloc d'exception.
→ Côté client : `createTournamentOnlineGame()` crée la partie, **l'attache**,
*puis* seulement y entre. **L'ordre est capital.**

### 5. 🔑 LA VRAIE CAUSE RACINE : décalage de type `bigint` / `uuid`
Confirmé en interrogeant directement la base : **tous** les appariements de
tournoi passés (y compris ceux résolus par timeout) avaient
`online_game_id = null`. Aucun n'avait jamais réussi à s'attacher, y compris
après les correctifs 1 à 4 ci-dessus.

`online_games.id` est de type **uuid**. Mais `tournament_pairings.online_game_id`
était en **bigint**, tout comme le paramètre `p_game_id` de
`tournament_attach_game()` et `tournament_report_from_game()`. Quand le client
appelait `tournament_attach_game(pairingId, g.id)` avec `g.id` un uuid, le cast
vers bigint échouait **systématiquement côté PostgreSQL** — la fonction
n'était jamais exécutée, `online_game_id` restait null pour toujours, et
l'adversaire attendait indéfiniment une partie qu'il ne trouverait jamais.

→ `tournaments_fix_uuid_mismatch.sql` : colonne et paramètres passés en uuid.
→ Correctif client associé (`index.html`, `renderMyPairing`) : le bouton
« Rejoindre la partie en cours » injectait `p.online_game_id` **sans
guillemets** dans l'attribut `onclick`. Un uuid contient des tirets ; non
guillemeté, JS les interprète comme des soustractions entre identifiants →
erreur de syntaxe muette au clic. Maintenant guillemeté.

## État à la reprise

Le correctif uuid/bigint (`tournaments_fix_uuid_mismatch.sql` + guillemetage
du bouton « Rejoindre ») **a été appliqué mais n'a pas encore été re-testé
par Jonathan en conditions réelles (2 comptes)**.

## Pistes si ça bloque encore

1. **Console F12** — le parcours est instrumenté, chercher les lignes `[tournoi]`.
2. **Vérifier que les deux joueurs sont bien dans la même partie** :
   ```sql
   select id, round, white_id, black_id, online_game_id, creator_claimed_by, result
   from tournament_pairings where tournament_id = <ID> order by round;
   ```
   `online_game_id` doit être **non nul et unique** pour l'appariement.
3. **Vérifier la poignée de main** :
   ```sql
   select id, white_player_id, black_player_id, ready_white, ready_black, status
   from online_games where id = <GAME_ID>;
   ```
   Si `ready_white` et `ready_black` sont vrais mais que le plateau reste
   masqué → le bug est dans `beginOnlineMatchStart()`.
   Si l'un des deux est faux → ce joueur n'a jamais appelé `markReady…`, donc
   il n'est pas dans cette partie.
4. **Suspect résiduel** : `closeMyOtherActiveOnlineGames(gameId)` est appelé au
   début de `enterOnlineGame()`. Si un joueur avait déjà une partie active, elle
   est fermée — vérifier que ça ne ferme pas la partie de tournoi elle-même.

---

# Protocoles de test AXE 1

Jonathan teste avec **2 comptes** (téléphone + PC, ou 2 navigateurs).
**Toujours ouvrir la console F12.**

## ☐ Tournois — parcours nominal
1. PC : Tournoi → 3 boutons de création (3s max 64 · 5s max 32 · 10s max 16).
   Créer un **3s** (délai de ronde le plus court : 3 min).
2. Téléphone : le tournoi apparaît → **S'inscrire**.
3. PC : lire « **2 inscrits → 2 rondes de 3 min max** » (rondes adaptatives).
4. Lancer la 1re ronde → compte à rebours + appariement visible des deux côtés.
5. **⚔ Jouer la partie** → la partie doit se lancer pour les deux.
6. Fin du combat → résultat reporté **automatiquement**, 🏮 Mon +2.
7. Ronde 2 → tournoi **Terminé**, podium (20 Mon au 1er).

## ☐ Tournois — désertion (code neuf, jamais validé)
1. Tournoi 3s, 2 inscrits, lancer la ronde.
2. **Ne rien reporter**. Attendre les 3 minutes.
3. → « ⌛ Délai écoulé » + bouton **« Adversaire absent — réclamer la victoire »**.
4. Cliquer depuis **un seul** compte → victoire par forfait, l'autre passe en
   **abandon** (grisé au classement), et le tournoi continue.

## ☐ Guildes
Créer (adhésion ouverte / sur demande), rejoindre, approuver une demande,
quitter (le chef part → promotion auto du plus ancien), défier une autre guilde.

## ☐ Ligue
Gagner une partie en ligne → points de Ligue crédités (3s→3, 5s→2, 10s→1).
Vérifier qu'une **défaite ne retire rien** (anti-tanking). Classement du groupe.

## ☐ Paliers de monnaie
Atteindre un palier (30/75/150) → il devient **cliquable** (halo doré) →
réclamer → bonus versé dans la monnaie du mode, puis coche verte.

## ☐ Boucle quotidienne
Défi du jour (1 tentative), 3 quêtes, 1re victoire du jour (+1 🍄),
série avec 48 h de grâce, Défi Rush (3 min / 3 erreurs).

## ☐ Partage de partie
Écran de fin → partage → image du plateau générée, partage natif sur mobile.

---

# Vérifications déjà validées ✅

- **Matchmaking** — réparé (RLS + fenêtre ELO élargissante). *Confirmé par
  Jonathan : « Loué soit le soleil ! »*
- **Défis entre joueurs** — fonctionnent.
- **WurmzSkin** — orientation, couverture totale du pion, visible par
  l'adversaire. Validé.

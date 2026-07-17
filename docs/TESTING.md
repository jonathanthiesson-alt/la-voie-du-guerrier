# Tests & état des lieux — AXE 1

---

# ✅ RÉSOLU ET VALIDÉ : les tournois (2026-07-14)

**Confirmé par Jonathan en conditions réelles (2 comptes) : « le tournoi
marche très bien ».** Le système est désormais entièrement automatisé côté
serveur. Cette section résume les leçons pour ne pas re-tomber dans les
mêmes pièges.

## Fonctionnement actuel

- **Clôture des inscriptions** : bouton « Clôturer les inscriptions et
  démarrer » visible **uniquement par le créateur** (vérifié côté serveur
  dans `tournament_close_registration` — `tournament_start_next_round`
  n'est plus appelable directement par les clients).
- **Rondes automatiques** : `pg_cron` exécute `tournament_cleanup()`
  toutes les 20 s. Forfaits soldés, rondes enchaînées, podium distribué —
  sans aucune action des joueurs.
- **Forfaits** : délai de grâce de 90 s après l'échéance pour laisser le
  joueur présent cliquer « Réclamer la victoire » (qui désigne le bon
  absent) avant que le tick ne solde en double-abandon.
- **Écran d'état de la ronde** : Ronde X/N, décompte, compteur de matchs
  terminés, liste en cours / en attente / terminés
  (`tournament_round_matches`).
- **Fin de partie** : pas de bouton Revanche, « Retour au tournoi »
  ramène sur le classement.

## Leçons apprises (bugs réels, dans l'ordre de découverte)

1. **Décalage de type `bigint`/`uuid`** — LA cause racine du blocage
   historique : `tournament_pairings.online_game_id` en bigint face à
   `online_games.id` en uuid → cast en échec systématique côté PostgREST,
   l'attachement n'aboutissait jamais, **silencieusement**.
   → `tournaments_fix_uuid_mismatch.sql`.
2. **uuid non guillemeté dans un `onclick`** — les tirets d'un uuid sont
   lus comme des soustractions → erreur de syntaxe muette au clic.
3. **Course à la création** : les deux joueurs cliquent « Jouer », chacun
   crée sa partie. → réservation atomique `FOR UPDATE`
   (`tournament_claim_creation`) + libération dont l'ancienneté (≥10 s)
   est vérifiée **par le serveur**, jamais sur parole du client
   (`tournaments_claim_race.sql`).
4. **`G = {...}` dans `enterOnlineGame()` est un REMPLACEMENT complet** :
   tout champ posé sur `G` avant l'appel est écrasé silencieusement.
   Poser les champs de contexte (tournoi, arène) **APRÈS**. Ce piège a
   frappé deux fois (Arène, puis tournois).
5. **Notification dans la même transaction que l'essentiel** : si
   l'insert de notification échoue, tout est annulé. Isoler le confort
   dans un bloc d'exception, faire l'essentiel d'abord.
6. **`endGame()` doit être gardée contre le double appel** (écho temps
   réel du même coup) : `if(G.gameOver) return;` en tout premier, sinon
   stats/XP/overlay rejoués une seconde fois.

---

# Protocoles de test AXE 1

Jonathan teste avec **2 comptes** (téléphone + PC, ou 2 navigateurs).
**Toujours ouvrir la console F12.**

## ☐ Défis entre amis (code neuf 2026-07-14, à valider)
1. Écran Amis : cliquer le **pseudo** d'un ami → sa carte de combattant.
2. Bouton **⚔** sur la ligne d'ami → popup de défi : mode (Partie rapide /
   Arène BO3), cadence (3/5/10s), enjeu (Compétitive / Amicale).
3. Fenêtre de chat : boutons 👤 (profil) et ⚔ (défi) en en-tête.
4. **Défi amical** : à la fin, vérifier « 🤝 Partie amicale — aucun impact
   sur l'ELO » et qu'ELO/Shiso/points de Ligue/XP n'ont **pas bougé**.
5. **Défi d'Arène** : vérifier que les DEUX joueurs entrent bien en BO3
   (écran de fin de manche, alternance des couleurs), et qu'une Arène
   amicale ne rapporte **aucun Koku**.
6. **Revanche après partie amicale** : doit rester amicale.

## ☐ Guildes ← en cours (audit + refonte défis le 2026-07-14)
**Audit fait** : rôles/plafond 20/promotion du chef déjà corrects côté
serveur ; ids en bigint (pas de piège uuid). **Corrigé** : la faille
`guild_contribute_ryu` (montant libre client — triche illimitée) est
supprimée ; le Ryu n'était de toute façon JAMAIS gagné (RPC jamais
appelé) ; les défis inter-guildes étaient une coquille vide (scores
jamais écrits, insert direct ouvert à tout membre).

**Nouveau fonctionnement (guilds_v2.sql)** : victoire en ligne classée
= +2 Ryu (perso + collectif), vérifiée en base par `guild_report_win`
(partie finie, gagnée par l'appelant, classée, non déjà comptée). Défi
inter-guildes : chef uniquement, 48 h, +1 par victoire d'un membre,
clôture pg_cron (+30 Ryu à la guilde gagnante, égalité = personne).

Protocole (2 comptes) :
1. Compte A : créer une guilde SUR DEMANDE → B demande → A approuve.
2. B quitte, re-rejoint une guilde OUVERTE créée par B ? Non — B crée
   sa propre guilde (il faut 2 guildes pour un défi).
3. A (chef) lance un défi inter-guildes → vérifier que B (membre d'une
   autre guilde) voit le défi ; vérifier qu'un simple membre ne PEUT
   PAS défier (toast "Seul le chef...").
4. A bat B en partie en ligne CLASSÉE → écran de fin : "🐉 +2 Ryu · +1
   défi de guilde" ; vérifier le score du défi et le Ryu collectif.
5. Une victoire AMICALE ne doit rien créditer.
6. Le chef quitte → l'autre membre devient chef (👑).

## ☐ Ligue
Gagner une partie en ligne → points de Ligue crédités (3s→3, 5s→2, 10s→1).
Vérifier qu'une **défaite ne retire rien** (anti-tanking). Classement du groupe.
⚠ Le code des points a été modifié le 2026-07-14 (gating amical) — re-tester
qu'une victoire **classée** crédite toujours bien les points.

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

- **Tournois** — automatisation serveur complète (pg_cron), clôture
  créateur-seulement, forfaits, état de ronde, retour au tournoi. *Validé
  le 2026-07-14 : « le tournoi marche très bien ».*
- **Matchmaking** — réparé (RLS + fenêtre ELO élargissante). *Confirmé par
  Jonathan : « Loué soit le soleil ! »*
- **Défis entre joueurs** (liste en ligne) — fonctionnent.
- **WurmzSkin** — orientation (aucune rotation, l'asset est déjà dans le
  bon sens pour tous les rôles), couverture totale du pion, visible par
  l'adversaire. Validé.
- **UI / navigation basse** — écrans qui défilent jusqu'en bas malgré la
  barre de navigation, bulle Musashi plafonnée (ne repousse plus le
  plateau), boutons profil accessibles.

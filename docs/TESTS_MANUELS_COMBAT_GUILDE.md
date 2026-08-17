# Combat de guilde (G0→G8) — tests restant à faire à la main

> Généré le 2026-08-18 après la campagne de tests par bots (impersonation
> SQL) qui a validé toute la logique serveur lot par lot. Cette liste ne
> reprend PAS ce qui est déjà prouvé — voir `docs/ROADMAP_GUILD_BATTLE.md`
> § 10 pour le détail de chaque lot testé. Elle couvre uniquement ce qu'un
> bot ne peut pas exercer : l'interface, la simultanéité humaine réelle, et
> le temps qui passe vraiment (pas simulé par avance d'horloge SQL).

---

## Pourquoi ces tests n'ont pas pu être faits par IA

- **Aucun navigateur de test disponible cette nuit** (session sans preview
  actif sur ce projet) : tout l'écran (boutons, mise en page, retours,
  responsive mobile) n'a été vérifié qu'à la lecture du code, jamais cliqué.
- **Les bots ne chargent jamais une vraie partie** : ils prouvent que le
  moteur SERVEUR réagit correctement à l'absence (forfait, décompte),
  mais ne prouvent jamais qu'un vrai joueur peut réellement JOUER un duel
  du début à la fin (plateau, coups, victoire par mécanisme de jeu réel).
- **Le temps a été avancé par écriture SQL directe** (`update ... set
  starts_at = now() - interval ...`), jamais par une vraie attente de
  5 minutes ou 1 heure. Rien ne prouve que les cron pg_cron réels (20s)
  déclenchent bien ces mêmes transitions SANS coup de pouce.
- **Aucune simultanéité humaine réelle** : un seul compte à la fois dans
  les tests, jamais deux navigateurs ouverts en même temps qui cliquent
  au même moment (le vrai risque de bug de course).

---

## 1. Tournoi interne (G1-G5) — jamais testé en navigateur

- [ ] Ouvrir Guilde → 🥋 Tournoi interne, planifier un tournoi réel (date à
      ~20 min), vérifier que le formulaire refuse une date dans le passé.
- [ ] S'inscrire avec 6 comptes/appareils différents (ou 6 onglets), vérifier
      le compteur d'inscrits en direct.
- [ ] Attendre la vraie clôture des inscriptions (pas d'avance d'horloge) —
      vérifier que la notif « ⏳ Inscriptions closes » arrive sous 20-40s
      après l'heure prévue (marge du cron).
- [ ] Le chef répartit automatiquement (⚖), vérifie l'affichage des deux
      équipes, déplace un joueur manuellement avec le bouton « → Équipe X ».
- [ ] Attendre l'ouverture réelle du check-in (5 min avant le début),
      confirmer sa présence avec le vrai bouton, vérifier le badge ✅/⏳.
- [ ] Laisser UN joueur ne PAS confirmer sa présence — vérifier qu'il est
      bien retiré à l'heure du lancement et que les sièges se renumérotent
      sans trou à l'écran.
- [ ] Lancer réellement un duel : les deux joueurs REJOIGNENT la partie
      (bouton « ▶ Rejoindre mon duel » depuis la notif ET depuis l'écran),
      jouent un vrai coup, vérifient que le plateau s'affiche bien (couleurs
      Blanc=Équipe A / Noir=Équipe B).
- [ ] Un des deux joueurs NE REJOINT PAS sa partie — attendre les 60s réels
      de délai de grâce, vérifier le forfait automatique et l'élimination.
- [ ] Vérifier l'arbre Tekken (lot G5) en vrai : les flèches, la série de
      victoires (streak), le nœud doré cliquable pour spectate un duel en
      cours, en particulier sur MOBILE (le SVG n'a été vérifié qu'en
      desktop via un serveur statique local).
- [ ] Vérifier le journal de guilde (📜) affiche bien tous les événements
      (planification, clôture, résultat).

## 2. Confrontation amicale (G6) — jamais testée en navigateur

- [ ] Proposer une confrontation à une guilde réelle (Wurmz + Musashi ou 2
      comptes de test), vérifier la notif reçue CHEZ LE CHEF UNIQUEMENT
      de la guilde ciblée (pas les autres membres).
- [ ] Le chef adverse accepte — vérifier que TOUS les membres des deux
      guildes reçoivent bien la notif de confirmation.
- [ ] Tester le refus (✕) — vérifier la notif de refus chez le proposant.
- [ ] Vérifier que l'écran distingue clairement ce mode du Tournoi interne
      (couleur bleutée du bandeau d'intro, libellés "vs <nom de guilde>"
      au lieu de "Équipe A/B") — c'est la décision D du cadrage
      (« ne jamais confondre les trois systèmes »), jamais vérifiée à l'œil.
- [ ] Refaire le même parcours de duel/forfait qu'au § 1, mais avec les
      DEUX guildes réelles inscrivant chacune leurs propres membres.
- [ ] Cliquer une notif `guild_event_announced` reçue pendant une
      Confrontation amicale EN COURS et vérifier qu'elle ouvre bien l'écran
      Confrontation amicale, PAS le Tournoi interne (c'est le bug corrigé
      dans le lot G8 — `guildOpenEventByKindFromNotification` — jamais
      testé en conditions réelles, seulement par relecture du code SQL).

## 3. Attaque de guilde (G8) — jamais testée en navigateur, la plus risquée

- [ ] Déclarer une vraie attaque depuis l'écran (sélecteur de tranche à mon
      niveau/plus forte/plus faible) — vérifier que la liste de guildes
      candidates s'affiche correctement et que le clic « Attaquer »
      pré-remplit bien la bonne cible.
- [ ] Vérifier le message de confirmation JS (`confirm()`) avant déclaration
      — s'assurer qu'il est lisible sur mobile.
- [ ] Laisser tourner une vraie attaque du début à la fin avec de vrais
      comptes des deux côtés, vérifier l'affichage du Ryu volé et du delta
      d'Elo de guilde dans la notif ET dans le Journal de guilde.
- [ ] **Tester le scénario "défense zéro" en réel** : déclarer une attaque,
      NE PAS inscrire un seul défenseur, attendre les 5 vraies minutes
      avant le début, vérifier la notif d'annulation ET le mouvement de
      5 🐉.
- [ ] **Tester l'annulation côté attaquant** dans la vraie fenêtre de 1h
      avant le début (pas simulée), vérifier le bouton ✕ dans la liste et
      le message de confirmation.
- [ ] Vérifier que le bouton ✕ (annuler) est bien ABSENT/inopérant pour le
      chef de la guilde défenseure (l'attaque ne se laisse annuler que côté
      attaquant, décision R) — jamais vérifié à l'écran.
- [ ] 🔴 **Vérifier consciemment la limitation documentée** : faire forfait
      un défenseur (ne pas rejoindre sa partie) et CONFIRMER QUE Monban NE
      prend PAS le relais (comportement actuel, différent de la décision F
      — voir `docs/ROADMAP_GUILD_BATTLE.md` § 10, lot G8). Le forfait
      élimine simplement le défenseur absent, comme un Tournoi interne.
      Si Wurmz veut ce mode public, ce point doit être traité avant.
- [ ] Vérifier le classement des guildes (🏆 Autres guildes) : l'Elo de
      guilde affiché change bien de place au classement après une vraie
      attaque, et le Ryu reste affiché en dessous comme trésorerie.

## 4. Notifications & pastilles — jamais vérifiées à l'œil

- [ ] Pour chacun des 8 nouveaux types de notif de ce chantier
      (`guild_event_challenge_received/declined`, `guild_attack_declared/
      cancelled`, et les 4 déjà existants réutilisés) : vérifier l'icône
      dans le menu Notifications (pas le 🔔 générique par défaut).
- [ ] Vérifier que la pastille du bâtiment Arène (thème Village) s'incrémente
      bien pour ces 8 types — code déjà modifié dans les DEUX allowlists de
      `villageRefreshBadges()`, jamais rechargé dans un vrai navigateur.
- [ ] Vérifier qu'un clic sur CHAQUE type de notif route bien vers l'écran
      attendu (pas de faute de frappe dans un nom de fonction qui romprait
      silencieusement le clic).

## 5. Cas limites non couverts par les bots

- [ ] **Asymétrie réelle** (décision G) : un 4 contre 3 (pas testé par bots
      dans cette campagne, seulement du 4v4 symétrique) — vérifier que
      l'équipe à 3 peut quand même gagner/perdre normalement et que
      l'affichage de l'arbre gère bien des colonnes de hauteurs différentes.
- [ ] **20 contre 20** (le maximum, décision I) — jamais testé, ni par bot
      ni par navigateur. Risque de perf/lisibilité de l'arbre SVG avec 40
      nœuds, et durée réelle de 1h15-2h15 (décision I, risque déjà noté
      au § 9 du cadrage) — à mesurer en vrai dès que possible.
- [ ] **Deux événements simultanés pour une même guilde** (ex. Tournoi
      interne EN COURS + Confrontation amicale EN COURS en même temps,
      décision D) — vérifier que l'écran Guilde distingue bien les deux
      sans confusion, jamais recréé ce scénario en pratique.
- [ ] **Cooldown d'attaque à cheval sur minuit/changement de jour** — les
      cooldowns sont en heures réelles (7×24h / 4×24h), pas en jours
      calendaires, mais jamais vérifié que l'affichage compte juste pour
      le joueur (« encore 3 jours » etc. — actuellement aucun affichage de
      compte à rebours n'existe côté client, à ajouter si Wurmz le souhaite).

---

## Ce qui EST déjà prouvé (pour ne pas re-tester inutilement)

Toute la logique serveur : cooldowns, ciblage par tranche, formule Elo
(vérifiée à la décimale près), vol de Ryu, formules de pénalité Q/X,
annulation, verrou anti-double-événement, assignation d'équipe par guilde
d'origine, ordre de passage par Elo, forfait (absence des deux côtés ET
d'un seul côté), streak de victoires, notifications correctement adressées
aux bonnes personnes avec le bon texte. Voir le détail exact de chaque test
dans `docs/ROADMAP_GUILD_BATTLE.md` § 10 (une entrée par lot G0-G8).

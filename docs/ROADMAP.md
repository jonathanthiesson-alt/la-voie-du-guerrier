# Roadmap — les 6 axes

**[J]** = Jonathan (dev) · **[T]** = Thomas (graphismes) · **[J+T]** = les deux

---

## 🔵 AXE 1 — Stabilisation & tests en conditions réelles  ← **ON EST ICI**

**Objectif** : que tout ce qui a été construit fonctionne vraiment, testé à deux
comptes, avant d'ajouter quoi que ce soit.

| État | Sujet |
|---|---|
| ☐ | **Guildes** (adhésion, approbation, défis inter-guildes) ← prochain |
| ☐ | Ligue (points, classement de groupe, divisions, promotion/relégation) — était **totalement cassée** (RPC manquantes en base, jamais commitées) puis reconstruite avec le vrai modèle hebdomadaire/divisions le 2026-07-21, à tester à 2 comptes. |
| ☐ | Défis entre amis (profil, Arène/rapide, compétitif/amical) — codé le 2026-07-14, à valider à 2 comptes |
| ☐ | Paliers de monnaie cliquables |
| ☐ | Boucle quotidienne (défi du jour, quêtes, streak, Rush) |
| ☐ | Partage de partie |
| ✅ | **Tournois** — automatisés côté serveur (pg_cron), validés le 2026-07-14 |
| ✅ | Matchmaking (réparé : RLS + fenêtre ELO élargissante) |
| ✅ | Défis entre joueurs (liste en ligne) |
| ✅ | WurmzSkin |

**Règle** : ne pas passer à l'AXE suivant tant que l'AXE 1 n'est pas propre.
Jonathan a explicitement demandé un « hard focus axe 1 ».

---

## 🎨 AXE 2 — Direction artistique & production graphique  **[T]**

**C'est le goulot d'étranglement du projet.** Le jeu est fonctionnellement riche
mais la production graphique ne suit pas.

- Cohérence de la DA (samouraï féodal × cyberpunk)
- Skins de pièces, plateaux, thèmes
- Illustrations des adversaires IA (6 personnages)
- Bandeau de combat (poses illustrées)
- Assets marketing (captures, icônes de store)

---

## 📖 AXE 3 — Scénario & univers  **[J+T]**

Inspirations assumées : **Fate** (invocation de figures historiques) et
**Star Wars** (structure maître/disciple, chute).

- **Musashi** — le maître
- **Shinai** — ancien disciple de Musashi passé du côté sombre. C'est le
  « Vador » du récit.
- Campagne narrative, dialogues, progression

---

## 🔧 AXE 4 — Finitions applicatives  **[J]**

- ~~Brancher les tournois sur de vraies parties~~ ← **en cours, AXE 1**
- **Connexion via Google (OAuth)** — demandée le 2026-07-23. Bloquée côté
  Jonathan : créer un projet Google Cloud Console (écran de consentement OAuth
  + identifiants), URI de redirection à whitelister
  `https://ikssbshpvpqlcgrbjldz.supabase.co/auth/v1/callback`, puis activer
  le provider Google dans Supabase (Authentication → Providers) avec le
  Client ID/Secret obtenus. **Une fois ça fait, prévenir Claude** pour la
  suite côté code : bouton "Se connecter avec Google" + écran post-connexion
  (choix du pseudo + acceptation CGU/confidentialité/âge, puisqu'avec Google
  l'utilisateur arrive déjà authentifié, sans être passé par le formulaire
  d'inscription classique).
- Onboarding / tutoriel
- Notifications push
- Polish UI général
- ~~**Web Worker pour le simulateur d'équilibre Blanc/Noir**~~ — **FAIT le
  2026-07-26** via le nouvel outil **Laboratoire** (onglet DEV). Le calcul
  tourne dans un Web Worker (thread séparé, plus de gel, on peut naviguer
  pendant que ça tourne). Le couplage du moteur au `G` global a été contourné
  sans le découper : le Worker exécute une **copie exacte du moteur vivant
  extraite à l'exécution** (`Function.toString()` concaténé dans le script du
  Worker, voir `labBuildEngineSource`). Vérifié identique au bit près en mode
  déterministe. Verdict d'équilibre en direct avec significativité (σ).
- **LABORATOIRE — feuille de route** (validée par Jonathan le 2026-07-26,
  périmètre « tout, y compris worker serveur »). Chaque étape s'appuie sur la
  précédente ; l'ordre est contraint (le worker serveur a besoin du moteur
  extrait, déjà fait à l'étape 1).
  1. ✅ **Clé de voûte + Labo navigateur** — moteur extrait, Web Worker,
     verdict d'équilibre sur le format **standard**. Fait le 2026-07-26.
  2. ✅ **Formats en données** — fait le 2026-07-26 (dimensions puis pièces).
     Moteur rendu **agnostique aux dimensions** (`isValid`/`findMaster`/
     `evalPosition`/`allMoves`/`minimaxFn` lisent `G.rows`/`G.cols`, plus de 5×5
     en dur ; standard vérifié inchangé par régression). Formats **Sumo** et
     « Élargi 7×7 » ajoutés à `LAB_FORMATS`. **Éditeur de format** (JSON validé).
     **Nouveaux types de pièces (V0.31.0)** : `legalMoves` délègue tout type non
     natif à `labGenericMoves`, un **interpréteur de mouvement piloté par
     données** — primitives `slide` (glisse jusqu'à obstacle), `step` (1 case),
     `jumps` (sauts qui ignorent les obstacles), directions `ortho`/`diag`/`all`
     ou liste `[[dr,dc]…]`, options `range`/`capture`/`king`. Capture à
     l'échiquéenne, victoire tranchée dans `execMove` (roi = épéiste ou
     `king:true`). Démos **Lanciers 7×7** et **Cavaliers 5×5**. Le jeu live
     (3 pièces natives) est **strictement inchangé** : dérivation gardée par
     `G.pieceDefs` (absent en prod), régression déterministe identique. Limite
     connue restante : l'**éval** ne donne aux pièces custom qu'une valeur de
     matériel générique + pression vers le roi (pas de modèle de menace fin par
     type) → les verdicts d'équilibre sur formats custom sont préliminaires.
  3. ✅ **Worker serveur** — fait et VALIDÉ EN CONDITIONS RÉELLES le 2026-07-26
     via **GitHub Actions**. Objectif atteint : les simulations tournent **sans
     appareil allumé**, en **profondeur 4-5**, et s'accumulent dans
     `dev_balance_stats` (vérifié : écriture + cumul + exclusion des nulles OK).
     *Pivot assumé* : l'Edge Function Deno a été construite, déployée ET testée,
     mais le minimax prof. 4-5 **dépasse le budget CPU** d'une Edge Function
     (échec mesuré dès 3 parties en prof. 4 → `WORKER_RESOURCE_LIMIT`). Le même
     moteur extrait tourne sans limite en **Node**, et le repo est **public** →
     GitHub Actions y est gratuit/illimité. Solution retenue :
     `scripts/balance-worker.mjs` (lit `index.html` du checkout, extrait le
     moteur — source vivante, zéro dérive — simule, puis écrit **en direct** dans
     `dev_balance_stats` avec le `service_role`) + `.github/workflows/balance-worker.yml`
     (cron horaire + `workflow_dispatch`, ~100 parties/tick prof. 4). **Piège
     rencontré** : l'RPC `dev_record_balance_result` est gardée par
     `is_admin_user()` (exige un UTILISATEUR admin via `auth.uid()`), or le
     `service_role` n'est pas un utilisateur → « admin only ». D'où l'écriture
     directe dans la table (le `service_role` contourne la RLS), en agrégeant le
     lot en une écriture upsert sur la clé unique. **RESTE (côté Jonathan)** :
     supprimer l'Edge Function `balance-worker` déployée mais abandonnée
     (Dashboard → Edge Functions), non supprimable via l'outil MCP.
     **Enrichi le 2026-07-26** : (a) **anti-doublon** — chaque partie a une
     signature (sha1 de sa séquence de coups), stockée dans `dev_balance_games`
     (contrainte UNIQUE) ; seules les parties INÉDITES comptent (σ honnête).
     Ouverture serveur élargie à 6 demi-coups. (b) **Pilotage depuis le Labo** —
     table `dev_worker_config` + RPC admin + panneau « 🤖 Worker automatique »
     dans le Labo : marche/arrêt, profondeur **fixe** ou **cycle 4→5→6→4** (le
     runner avance le curseur à chaque tick), budget de temps (borne les runs en
     prof. 5-6). Config live actuellement **désactivée** (à activer depuis le Labo).
  4. ✅ **Éditeur de modes de jeu complet** — fait et vérifié le 2026-07-27
     (V0.32.0). Les 4 lots livrés, testés (28 tests unitaires moteur + smoke live).
     Le jeu standard reste **strictement inchangé** (garde `G.pieceDefs`/`mv.gpush`,
     absents en prod ; régressions déterministes identiques).
       - ✅ **Lot a — Modèle de pièce complet (moteur, piloté par données).**
         Poussée `push` (`true` | liste de types | `{chain,targets}`) + `pushable`
         (bords/void/sumo : hors sumo mur = illégal ; en sumo éjection, éjecter le
         roi adverse = victoire ; toute la résolution — file, éjections, victoire —
         pré-calculée dans `labGenericMoves`, appliquée par une branche `mv.gpush`
         dédiée d'`execMove`). Asymétrie déplacement≠capture (`captureStep`/
         `captureSlide`/`captureJumps`). Direction **relative à la couleur**
         (`forward`/`back`/`fdiag`/`bdiag`/`sideways`). Démo **Onis pousseurs sumo**.
       - ✅ **Lot b — Éditeur visuel (mini-plateau dans le Labo).** Grille
         interactive : dimensions ±, cases mortes cliquables, pose des pièces
         Blanc/Noir (construit `setup`), **aperçu des coups légaux** en surbrillance
         (moteur jetable via `new Function`, zéro dérive). Formulaire de type avec
         **gabarits** (Tour/Fou/Cavalier/Pion/Pousseur…) — point-and-click, aucun
         JSON requis (réponse au « JSON trop raide » pour Thomas/Musashi).
       - ✅ **Lot c — Cohérence & aller-retour.** Validation croisée (types
         référencés, `push.targets` existants), JSON ⇄ éditeur sans perte,
         **persistance** (localStorage → survit au reload) + un mode custom peut
         tourner sur le **worker serveur** (colonne `dev_worker_config.custom_format`,
         RPC + `balance-worker.mjs` mis à jour, migration appliquée 2026-07-27).
       - ✅ **Lot d — Éval par type.** `labPieceValue` : valeur `value` explicite ou
         **estimée par mobilité** (glisseur > sauteur > marcheur ; poussée ajoute,
         poussable retire) au lieu d'une valeur unique (22) → verdicts fiables.
  5. ☐ **Publier un format comme événement** — pont entre un format du registre
     et le système d'événements live (comme le Sumo), pour tester une variante
     auprès des vrais joueurs. Boucle « forger → tester → publier » bouclée.
- Performance sur mobile bas de gamme

---

## 📱 AXE 5 — Portage application native (Capacitor)  **[J]**

**Ne pas commencer trop tôt.** Repère donné par Jonathan : on porte quand les
correctifs quotidiens ralentissent, pas avant. Aujourd'hui on itère encore vite
sur le web, ce serait un frein.

À prévoir :
- **Capacitor** (le jeu est déjà un fichier HTML unique, ça devrait bien passer)
- **RevenueCat** — achats intégrés (le Koku est la monnaie premium)
- **Firebase** — notifications push
- **RGPD** — consentement, politique de confidentialité
- **Comptes développeur** : Apple 99 $/an · Google 25 $ une fois

---

## 🏷️ AXE 6 — Marque & jeu physique  **[J+T]**

- Identité de marque
- Édition physique du plateau (le jeu est un abstrait 5×5, ça se prête bien)
- Site vitrine

---

## Décisions structurantes déjà prises

Ces points ont été tranchés, ne pas les remettre en cause sans raison.

1. **Le Koku (石) ne se gagne JAMAIS en jouant.** C'est la monnaie premium.
   Elle n'entre que par la conversion de fin de saison et les achats.
2. **Une monnaie par mode** (Shiso, Tamashii, Mon, Ryu, Hanafuda) + le
   **Shiitake** transverse pour le quotidien.
3. **Saisons de 3 mois** : les monnaies de mode sont converties en Koku puis
   remises à zéro.
4. **Tournois = système suisse**, pas d'élimination. Plafonds par cadence
   (64/32/16) calibrés pour **~20 min** de tournoi. Désertion = abandon,
   le tournoi continue.
5. **Ligue anti-tanking** : on ne gagne que des points, jamais de perte.
6. **Modes coupables sans redéploiement** (drapeaux en base) — vital une fois
   sur les stores, où publier un correctif prend des jours.

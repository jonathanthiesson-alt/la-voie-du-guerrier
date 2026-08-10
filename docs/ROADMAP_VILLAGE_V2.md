# Roadmap — Réorganisation Village V2

> Issue du méga-brief de Jonathan (2026-08-10). Le **Village devient l'unique
> interface de jeu** ; les 3 autres thèmes (sumi, classique, wurmz) passent en
> **DEV only**. Ce document découpe le brief en **passes** pensées pour
> **minimiser la consommation de tokens** : `index.html` fait ~1,9 Mo, donc
> chaque passe ouvre **une seule région** du fichier, y fait TOUTES les modifs,
> et vérifie une fois. Le gros chantier serveur (tournois/admin/SQL) est isolé
> en fin de parcours.

---

## Principe de séquençage (coût tokens)

1. **D'abord les passes client « pas chères »** : réagencements pilotés par
   données (`VILLAGE_BUILDINGS`), déplacements d'items, renommages, nettoyages.
   Testables immédiatement dans le navigateur, aucun SQL.
2. **Regrouper par région de fichier**, pas par « bâtiment logique » : beaucoup
   de bâtiments sont data-driven dans le même tableau → une seule ouverture.
3. **i18n en une seule passe** en fin de chaque lot (clés fr/en/ja d'un coup).
4. **Le chantier tournois/admin en dernier** : c'est le seul qui touche SQL +
   outil admin + client → gros, à faire d'un bloc quand le reste est stable.
5. **Items bloqués par des assets** (image village détourée, monnaies, Port) →
   backlog, on ne les code pas tant que Thomas n'a pas fourni.

---

## PHASE 0 — Cadrage global

### 0.1 Thèmes DEV-only
- Verrouiller le sélecteur de thème : **seul Village** est proposé aux joueurs ;
  sumi / classique / wurmz **uniquement en mode DEV**.
- Vérifier qu'aucun parcours joueur ne peut retomber sur un autre thème.

### 0.2 Rappel de modèle mental (doc)
- **Village = menu principal / hub** (bâtiments = fonctionnalités).
- **Accueil = écran d'entrée** distinct (Se rendre au village, Combat rapide,
  2 joueurs, Pendule). Charrette = seul retour Village → Accueil. *(déjà en place)*

---

## PHASE 1 — Village : couche « carte » (1 passe, région VILLAGE_BUILDINGS + carte)

### 1.1 Bouton « Le saviez-tu » (ex « Le saviez-vous »)
- Renommer **partout** « Le saviez-vous » → **« Le saviez-tu »**.
- Le **retirer de tous ses emplacements actuels** et le déplacer sur un **petit
  bouton point d'interrogation en bas à gauche** de l'écran village.
- Bouton **détouré** (fond transparent pour laisser voir le village), au **tout
  premier plan cliquable**, devant les zones (arène, port, guilde, marché).

### 1.2 Bouton Sumo (à côté du « ? »)
- Logo **pion sumo**, détouré, même traitement visuel.
- **Petit timer** juste au-dessus indiquant la **fin de l'évènement sumo**.
- Clic → **mode sumo** dans l'évènement, **au château**.

### 1.3 Bouton Soleil = Bot army (vérifier)
- S'assurer que **Bot army** est bien accessible via le **Soleil** du village
  (raccourci DEV). Sinon l'y câbler. *(retiré de l'Arène — cf. Phase 3)*

### 1.4 Système de notifications village (code couleur)
- Les notifs suivent **en plus des actuelles** (messages…) les **quêtes
  journalières**.
- **Code couleur** :
  - **Tuto & système** (devlog, nouveau cosmétique débloqué : skins, avatars,
    plateaux, etc.) → une couleur.
  - **Quêtes journalières** → une couleur.
  - **Social** (messages…) → une couleur.
  *(palette à figer à l'implémentation ; 3 catégories minimum)*

---

## PHASE 2 — Château & Dojo (1 passe, data-driven + écrans concernés)

### 2.1 Château
- **Déplacer « Défi du jour » Château → Dojo** (cf. 2.2).
- **Campagne** : bouton dans Château → popup **« en chantier »**.
- **Recréer une case « Tuto »** dans laquelle on **déplace « Règles » et « La
  Voie du Bousier »**.
- **Quête du jour → « en chantier »** : retirer le contenu actuel et laisser
  **uniquement un bouton « en chantier »** (pas d'ébauche de quêtes pour l'instant).

### 2.2 Dojo
- Accueille désormais **Défi du jour**.
- **Supprimer « IA »**.
- **« Maîtres IA » → « Adversaires »**.
- **« Adversaires notables »** : inchangés.
- **Karakuri** rejoint **Adversaires notables**.
- **Supprimer « Shin-AI »** (déjà présent dans Adversaires notables).
- **Règles** : déjà rebasculé dans Tuto (cf. 2.1) → retirer du Dojo si résidu.

---

## PHASE 3 — Arène : nettoyage + carrousel + journal (1 passe, écran arène)

### 3.1 Nettoyage des entrées
- **Retirer** de l'Arène : **Ligue**, **Classement**, **Bot army**
  (Bot army migré au Soleil — cf. 1.3).
- **Supprimer tous les « en ce moment. »**.

### 3.2 Bandeau publicitaire + lisibilité
- **Élargir le bandeau pub au maximum** : supprimer les marges gauche/droite qui
  font perdre beaucoup de place.
- **Typographies un peu plus lisibles** au passage.

### 3.3 Journal (repart de zéro)
- **Supprimer** les citations Musashi et tout le format actuel.
- Nouveau principe : **chaque journal affiche les infos du menu où il se
  trouve** — en tournant le carrousel, il montre les infos de l'élément
  sélectionné.
- Dans l'Arène, le journal ne donne que des **infos liées aux tournois** : qui a
  gagné tel tournoi, etc.
- **« Le saviez-tu » de l'Arène → infos du/des tournoi(s) en cours.**

### 3.4 Modes de combat
- **Conserver** le carrousel et le **bandeau pub** (élargi, cf. 3.2).

---

## PHASE 4 — Refonte Tournois (ÉPIC : SQL + Admin + Client) — ✅ LIVRÉE (V0.62.0)

> Le seul lot qui touche **base + outil admin + client**. À faire d'un bloc,
> après stabilisation des phases 1–3.
>
> **État (2026-08-11)** : Lot A (SQL `tournaments_v4_admin.sql`) appliqué via
> MCP ✅ · Lot B (section admin « 🏆 Tournois ») ✅ · Lot C (écran joueur
> refondu + popup présentation) ✅. **Reste à valider en conditions réelles**
> (voir la liste de tests). Le classement Élo affiché reste à brancher sur un
> vrai Élo serveur (aujourd'hui le classement suisse par points est conservé).

### 4.1 Modèle & droits
- **Les joueurs ne créent plus de tournois.** Création/déclenchement **réservés
  à l'admin**.
- Clic « Tournois » → choix **Tournoi individuel** / **Tournoi de guilde**.
- **Classement par Élo**.

### 4.2 Outil admin — paramètres par tournoi
- **Public** : réservé **abonnés** (récompenses plus précieuses) **ou** **freemium**
  (non abonnés) — récompenses **gérées indépendamment** pour chaque catégorie.
- Paramétrable **indépendamment** :
  - type de tournoi (individuel / guilde),
  - **mode de jeu**,
  - **attribution des récompenses**,
  - **horaire de début**,
  - **créneaux** : périodes d'inscription, **durées des rounds**, **cadences**,
  - **texte de présentation** affiché dans le menu à la **première connexion**,
    **recliquable** via un petit **« ? » info** à côté de « Tournois »
    (lore, présentation, cadences, durée…).

### 4.3 Client
- Écran Tournois refondu (individuel/guilde, Élo).
- Popup de présentation (première connexion + recliquable via le « ? »).
- Suppression des chemins de **création par le joueur**.

---

## BACKLOG — bloqué par assets / à planifier

- **[Assets] Image du village** : fournir le **PNG** de fond **et** une version
  **bâtiments détourés** (vrais contours pour l'esthétique UI). Image
  **définitive** à venir de Thomas. → dès réception, passe « contours cliquables ».
- **[Économie] Refonte de toutes les monnaies** (Marché). Sinon **on ne touche à
  rien** au Marché pour l'instant.
- **[Port]** : reste **« en chantier »** (« c'est long dis donc »).

---

## Bâtiments OK (aucune modif)
Guilde · Maison · Auberge · Archives · Charrette (retour accueil, parfait).

---

## Annexe A — Quêtes journalières

Reporté. Pour l'instant : **bouton « en chantier »** uniquement, aucune quête
définie. Les quêtes réelles seront conçues plus tard (probablement en lien avec
la refonte des monnaies).

# UI « Village » — menu graphique (thème expérimental)

> Nouveau thème d'interface **`village`**, sélectionnable depuis l'écran
> d'accueil au même titre que `sumi` / `wurmz` / `classique`. **C'est un test** :
> tant qu'il n'est pas validé, on n'y bascule pas par défaut. À terme, s'il
> tient la route, il deviendra l'UI unique.
>
> Décisions prises avec Jonathan le 2026-08-09. Rien n'est codé tant que ce
> doc n'est pas relu.

## Principe

Le thème `village` **remplace la bottom-nav** par une **carte panoramique**
d'un village féodal (image large, défilable gauche/droite au drag/swipe). Les
**bâtiments = boutons** : chaque bâtiment cerclé dans la maquette ouvre les
**écrans existants** (`showScreen`), tels quels. On ne réécrit PAS les
sous-menus — le village est un **routeur graphique** par-dessus l'app.

- **Ne touche pas** aux thèmes `sumi`, `wurmz`, `classique` : ils gardent la
  bottom-nav. `village` = 4ᵉ thème, classe body `ui-village`.
- **Ne touche pas** au jeu 5×5 live, ni aux écrans eux-mêmes.
- **Bâtiments cliquables uniquement ceux cerclés** dans la maquette : Château,
  Arène, Maison, Guilde, Archives, Auberge, Port, Dojo, Marché + le **Soleil**
  (zone cachée). Le reste (torii, chariot, cascade, statues, lune…) = décor.
- **Contour lumineux** (halo doré) au survol/tap sur les zones cliquables pour
  signaler l'interactivité.
- **Non connecté** : les bâtiments à fonctions online sont **grisés** (toast
  « connecte-toi ») ; seules les fonctions locales restent actives (Dojo, etc.).

## Répartition des bâtiments → contenu

### 🏯 Château
- **Défis du jour** + **quêtes**.
- **Events scénaristiques / saisonniers** (PNJ, lore d'ambiance) — enrobent la
  campagne. La campagne *jouable* est au Dojo (le Château, c'est le récit).
- ⚠️ L'**event Sumo** ne va PAS ici → il va à l'**Arène** (voir plus bas).

### ⛩️ Arène (bâtiment PVP — à ne pas confondre avec le *mode* Arène)
- **Le carrousel** de modes PVP : Partie rapide, Arène (mode), Tournoi,
  **Champ de bataille**, **Sumo** (le mode ET son event).
- **Joueurs en ligne** (liste actuellement dans Social).
- **Ligue** : reste ici pour l'instant (jeu + accès). On la déplacera peut-être
  vers Archives après tests d'ergonomie.

### 🏠 Maison
- **Profil**, **Options / Paramètres**, **Affichage**, **Langue**,
  **Apparence / thèmes**, **skins** (pièces), **écran d'accueil (logo)**,
  **confidentialité du compte**, **écran Identité**.
- **Menu DEV** (bouton violet) — **visible uniquement aux comptes dev**
  (Wurmz/Musashi). ⚠️ **Décision** : le DEV vit ICI, **pas** sous le Soleil.

### 🏘️ Guilde
- **Chat de guilde**, membres, gestion, **matchs / défis inter-guildes**,
  toutes les fonctionnalités de guilde.

### 📜 Archives
- **Statistiques**, **Records**, **Succès**.
- **Lore** (désormais visible des joueurs) + **Citations**.
- **Classements** (leaderboards).
- **Derniers combats** : on déplace ici la modale **perso** existante (mes
  parties) — pas de flux global pour l'instant.
- **Série de connexion (streak)**.
- **Journal d'activité** (fil serveur : connexions, parties, guildes, tournois,
  arène…). **Ajout demandé** : cases à cocher pour **filtrer** le feed par type
  d'activité (guildes / tournois / parties / arène / …).

### 🍶 Auberge
- **Social** : gestion des **amitiés**, **messagerie**.
  (⚠️ *hors* « joueurs en ligne » → Arène, *hors* chat de guilde → Guilde.)
- **Forums** : **bouton vide** menant à un message « en cours de dev »
  (le vrai forum = chantier ultérieur, tables Supabase à part).
- **DevLog** (journal des mises à jour du jeu).
- **News** (com' distincte du DevLog : messages produits aux joueurs).
- **« Le saviez-vous ? »**.

### ⚓ Port
- **Vide pour l'instant.** Servira plus tard à **changer de village**.
  → zone cliquable qui affiche un « bientôt » (comme Forums).

### 🥋 Dojo
- **Campagne** (jouable).
- **Bots (IA locales)**, regroupés en une catégorie : **IA**, **Maîtres IA**,
  **Adversaires notables**. (⚠️ distinct de la *bot army* / équipe des 15, qui
  sont les bots *en ligne* — pas ici.)
- **Karakuri** (trainer) + **Shin-AI**.
- **2 joueurs même appareil**, **Pendule**, **Règles**.

### 🏪 Marché
- Toute la **Boutique**.

### ☀️ Soleil (zone cachée)
- **Raccourci vers le menu DEV**, **visible/cliquable uniquement pour les
  comptes dev** (Wurmz/Musashi). Doublon pratique de l'entrée DEV de la Maison
  (les deux mènent au même `dev-hub`). Pour les non-devs, le Soleil est du décor
  (zone non cliquable). Un éventuel easter-egg viendra plus tard.
- La **bot army** est accessible depuis le menu DEV — plus au-dessus du
  carrousel online.

## Notes techniques

- 4ᵉ thème : `UI_THEMES = ['classic','sumi','wurmz','village']`, classe
  `body.ui-village`, persistée dans `localStorage vtl_ui_theme` (mécanique
  `setUiTheme` existante). Sélecteurs `.uitheme-btn` (Apparence + Affichage) et
  cycle `cycleUiTheme` à étendre.
- `body.ui-village` : masque `#bottom-nav`, affiche un conteneur carte
  `#village-map` (panoramique) sur le hub. Les écrans de contenu restent
  inchangés ; un bouton « ↩ Village » remplace le retour bottom-nav.
- Zones cliquables = calques positionnés en % au-dessus de l'image (responsive),
  pas des coordonnées en dur px → tiennent au redimensionnement.
- Grisage online : réutiliser l'état de session (`currentUser`) pour
  `classList.toggle('locked', !online)` sur les bâtiments online.
- i18n : chaînes FR littérales pour le test (comme Labo) → `LANGS` non touché
  tant que le thème n'est pas validé.

## Bloc 1 livré (V0.43.0, 2026-08-09)

- **Bandeau du haut** (`#village-topbar`) : koku + monnaies de mode
  (`MODE_CURRENCIES`) + rang de Ligue (lazy `get_my_league_standings` →
  `LEAGUE_TIERS`). `villageRefreshBanner()`/`villageFetchLeagueTier()`.
- **Halo permanent + nom affiché** sous chaque bâtiment (CSS `.village-zone`
  `::before`/`::after`, plus de hover-only).
- **Pastilles de notif** : Arène (notifications non lues) + Auberge (DM non
  lus) — `villageRefreshBadges()` ; item **Notifications** ajouté à l'Auberge.
- **Navigation centrale** : `villageInterceptBack` (écouteur en capture) —
  en `ui-village`, tout bouton retour `.screen-nav-bar .tuto-nav-btn` remonte
  à l'écran précédent réel (historique, hubs exclus) ou au village. Le bouton
  flottant ⛩ Village reste le retour rapide universel.

## RESTE (Blocs 2 & 3, cross-cutting)

- **Bloc 2 — Gestion de guilde** (par le GM) : bannière + devise + message
  d'info, popup à la 1re connexion depuis un nouveau message, devise au
  5-4-3-2-1 des matchs de guilde (comme les devises de joueurs). Nécessite des
  **tables Supabase** → `sql_a_executer/` (à relire/exécuter par Jonathan).
- **Bloc 3 — Minuteur type échecs** (cœur du jeu, TOUS les modes) : timer
  déclenché au **1er coup des Blancs** ; si >10 s pour ce 1er coup → partie
  annulée (amical) / défaite + ronde suivante (arène/tournoi).

## Découpage proposé (phases testables)

1. **Squelette thème** : `ui-village` sélectionnable, carte panoramique
   défilable, zones cliquables + halos, masquage bottom-nav, retour « Village ».
2. **Routage** : chaque bâtiment → `showScreen` du/des écran(s) correspondants ;
   grisage online ; Port/Forums « bientôt ».
3. **Réagencements de contenu** qui n'existent pas encore à l'endroit voulu :
   News (nouveau), filtres du Journal d'activité, regroupement bots du Dojo,
   déplacements (joueurs en ligne → Arène, streak/derniers combats → Archives…).
4. **Finitions** : responsive mobile, contrôle 3 passes, version + changelog +
   mémoire.

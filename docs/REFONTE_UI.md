# Refonte UI « fluide façon chess.com » — plan validé (2026-07-18)

> Décisions prises avec Jonathan AVANT le chantier. À exécuter en
> **3 phases = 3 commits testables**, dans l'ordre. Ne pas tout faire
> d'un coup. Vérifier dans le navigateur à chaque phase.

## Objectif

Lancer une partie en **2 clics** (onglet → cadence), une organisation
claire En ligne / Local, et un logo d'accueil configurable en raccourci.

## Nouvelle organisation des 5 onglets (bottom-nav)

| Onglet | Contenu |
|---|---|
| **⚔ JOUER** (en ligne) | En tête : widget quotidien (défi du jour + quêtes + streak, inchangé). Puis **CTA principal : Partie rapide 3s / 5s / 10s qui LANCENT LA RECHERCHE immédiatement** (le vrai 2-clics). Dessous, en cartes : Arène, SUMO/Événements, Tournois, Ligue, **Guildes**, Classements. |
| **🏠 LOCAL** (ex-Campagne) | Campagne Musashi, Maîtres IA, Adversaires IA, Entraînement (défis libres + Rush), Pendule, 2 joueurs sur un appareil, futures fonctionnalités locales. |
| **🏪 BOUTIQUE** | inchangé |
| **👥 SOCIAL** | Amis, messages, **+ accès au canal de discussion de la guilde** (voir ci-dessous) |
| **侍 PROFIL** | inchangé + **bouton ⚙ Options juste AU-DESSUS de « mon message en combat »** |

### Le bouton ⚙ Options (dans Profil)
Absorbe l'ancien « Menu complet » : réglages du jeu, Affichage,
Apparence, écran d'accueil, déconnexion, panneau admin (Wurmz/Musashi).
Objectif : tuer un niveau de navigation.

### Guildes — décision spécifique
- Le menu Guilde reste dans **JOUER (en ligne)** avec : autres guildes,
  défis inter-guildes, membres, **et un CHAT DE GUILDE** (nouveau — à
  créer, canal de discussion des membres).
- Le **même chat de guilde est AUSSI accessible depuis SOCIAL** (double
  porte d'entrée, une seule implémentation).

## Logo d'accueil = raccourci configurable (rattaché au compte)

- Stockage : `profiles.appearance_prefs` (jsonb existant) → **aucun
  script SQL nécessaire**.
- Réglage dans ⚙ Options : le joueur choisit l'action du logo parmi :
  1. Lancer une partie rapide 5s
  2. Lancer un combat d'Arène 10s
  3. Lancer le défi du jour
  4. Aller à la page Événements
  5. Aller à la page Social
  (prévoir « Aucun » pour désactiver)
- **Par défaut : rien** (logo décoratif, zéro clic accidentel).
- **Une fois activé : une aura transparente légère autour du logo**, et
  le joueur choisit **la COULEUR de l'aura** dans les mêmes paramètres.
  L'aura est le signal visuel « le logo est un bouton ».
- Non-connecté : les actions en ligne échouent proprement (toast +
  invitation à se connecter).

## Phasage (3 commits)

- **Phase A — Réorganisation des onglets** : renommage Campagne→Local,
  redistribution des écrans/entrées entre JOUER/LOCAL/SOCIAL, bouton
  ⚙ Options dans Profil (au-dessus de « message en combat »), absorption
  du Menu complet. NAV_TAB_MAP à mettre à jour.
- **Phase B — Le 2-clics** : CTA Partie rapide 3s/5s/10s en tête de
  JOUER (recherche lancée direct), cartes de modes, chat de guilde
  (nouvelle fonctionnalité, double accès JOUER+SOCIAL).
- **Phase C — Logo-bouton** : réglage dans Options (action + couleur
  d'aura), aura CSS autour du logo, exécution du raccourci, garde
  non-connecté, stockage dans appearance_prefs.

## Rappels techniques (leçons du projet)

- Vérif syntaxe + profondeur d'accolades après CHAQUE édition (CLAUDE.md).
- `.btn` a `width:100%` par défaut — toujours `width:auto;flex-shrink:0`
  dans les rangées flex.
- Ne jamais nommer une colonne toute neuve dans un select critique.
- Le logout doit rester accessible (il vivra dans ⚙ Options).
- i18n : 195 clés × 3 langues si on ajoute des clés LANGS.

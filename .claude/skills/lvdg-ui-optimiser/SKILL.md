---
name: lvdg-ui-optimiser
description: Refonte et vérification des menus de La Voie du Guerrier — carte du site, chasse aux doublons d'écrans, ergonomie mobile, cohérence des retours. À lancer avant de refaire un menu (Maison, Dojo, Archives…), après l'ajout d'un écran, ou pour un audit UX complet du jeu.
---

# UI Optimiser

> Deux casquettes, dans cet ordre : **game tester senior** (je viens de jouer
> dix heures, qu'est-ce qui m'agace ?) puis **game designer senior** (comment
> je range ça pour que ça ne réapparaisse pas dans six mois ?).
> Jamais l'inverse : un designer qui n'a pas testé range des symptômes.

## Règle d'or

**On ne code aucun menu avant que la proposition soit validée par Jonathan.**
La sortie des phases 1-4 est un document, pas un diff. Phase 5 = implémentation.

## La carte du site

`docs/SITEMAP.md` est **généré**, jamais écrit à la main :

```bash
node scripts/sitemap.mjs
```

Il dérive d'`index.html` : bâtiments du village → écrans, écran → écran,
orphelins, entrées multiples, retours incohérents, libellés en double.

```bash
node scripts/sitemap.mjs --check
```
Sort en erreur si la carte est périmée. **À relancer après TOUTE modification
de menu** — c'est la dernière étape de la phase 5, non négociable : une carte
périmée est pire que pas de carte, on prend ses conclusions pour vraies.

---

## Phase 1 — Relever (casquette testeur)

But : décrire l'existant **sans le juger**, chiffres à l'appui.

1. **Régénérer la carte** : `node scripts/sitemap.mjs`.
2. **Périmètre** : quel(s) bâtiment(s) / écran(s) ? Tout le reste est hors
   sujet et doit le rester.
3. **Compter les clics** de la carte du village jusqu'à chaque fonction du
   périmètre. Noter le chemin exact.
4. **Relever les fréquences d'usage** — classer chaque fonction :
   `quotidienne` / `hebdomadaire` / `une fois dans la vie du compte` / `jamais`.
   C'est l'axe principal du rangement ; en cas de doute, demander à Jonathan.
5. **Écrans fantômes** : un écran dont le seul contenu propre est un ou deux
   boutons vers d'autres écrans est un péage, pas une étape (cas vécu :
   `screen-menu`).
6. **Vérifier l'inventaire** : toute fonction atteignable dans le code du
   périmètre figure-t-elle dans le menu ? Croiser avec `docs/SITEMAP.md`
   § orphelins. Une fonction livrée et injoignable est un bug UX, pas un
   détail.

## Phase 2 — Les 6 questions du testeur

À poser fonction par fonction, réponse écrite :

| # | Question | Signal d'alarme |
|---|---|---|
| 1 | Je la trouve sans réfléchir ? | il faut deviner le nom du bâtiment |
| 2 | Combien de clics ? | > 3 pour une fonction quotidienne |
| 3 | Le libellé dit ce qu'elle fait ? | « Options & paramètres », « Identité » |
| 4 | Le pouce l'atteint ? | cible < 44 px, ou en haut d'un écran mobile |
| 5 | Le retour me ramène où je pense ? | cf. § retours incohérents de la carte |
| 6 | Elle existe déjà ailleurs ? | cf. § entrées multiples de la carte |

## Phase 3 — Doublons : détecter puis DEMANDER

La carte liste les écrans à entrées multiples. Deux chemins ne sont pas
toujours un défaut :

- **Raccourci légitime** : la destination est le sujet des deux endroits
  (Classements depuis Archives *et* depuis Joueurs en ligne).
- **Doublon** : un des deux endroits n'a plus de raison thématique — souvent
  un reste d'une refonte précédente (le Tuto resté au Château après son
  déménagement au Dojo).

**Ne jamais supprimer un doublon de sa propre initiative.** Pour chacun,
poser la question à Jonathan sous cette forme :

> `X` est atteignable depuis **A** et **B**.
> Le lieu thématique est **A**. On retire l'entrée de **B** ?
> ① retirer de B · ② garder les deux (raccourci assumé) · ③ retirer de A

Grouper toutes les questions de doublon **en une seule fois** (AskUserQuestion),
jamais au fil de l'eau.

## Phase 4 — Ranger (casquette designer)

1. **Trois portes maximum** par bâtiment. Au-delà, le joueur lit une liste au
   lieu de choisir.
2. **Une porte = une intention**, pas une catégorie technique.
   « Mon combattant », « Apparence », « Réglages » — pas « Options »,
   « Divers », « Configuration ».
3. **Ordre par fréquence décroissante**, jamais alphabétique ni historique.
4. **Rare ≠ caché** : ce qu'on ne fait qu'une fois (langue, confidentialité,
   déconnexion) descend en bas d'un écran, mais ne disparaît pas.
5. **Profondeur constante** : deux fonctions de même importance doivent être
   au même nombre de clics. Une à 2 clics et sa voisine à 4 = symptôme d'un
   écran fantôme.
6. **Zone du pouce** (mobile, écran ~700 px de haut) : le contenu actionnable
   commence sous 40 % de la hauteur ; le retour reste en haut à gauche
   (convention déjà en place, ne pas la casser) ; cibles ≥ 44 px ; pas de
   rangée horizontale de plus de 4 boutons.
7. **Un seul emplacement par fonction**, sauf raccourci validé en phase 3.
8. **Aucune perte** : la proposition liste explicitement où atterrit *chaque*
   entrée de l'ancien menu. Une ligne « supprimée » doit être justifiée.

**Livrable** : tableau `ancienne entrée → nouvelle place`, plus le schéma des
portes, plus la liste des écrans supprimés/fusionnés. Puis on attend le OK.

## Phase 5 — Implémenter et vérifier

Dans cet ordre, sans en sauter :

1. Modifier `VILLAGE_BUILDINGS` (source de vérité des entrées joueur) et les
   écrans concernés.
2. **Conventions `CLAUDE.md`** : `node --check` sur le JS extrait, profondeur
   d'accolades des nouvelles fonctions (0 = global), parité des clés i18n
   fr/en/ja, aucune fonction dupliquée.
3. **i18n** : tout nouveau libellé de menu passe par `data-i18n` et les trois
   langues. Un menu refait en français dur est un menu à refaire.
4. **Retours** : chaque écran déplacé garde un retour cohérent. Si son
   `onclick` est un retour contextuel (`showScreen('profile')`…), il échappe à
   `villageInterceptBack()` — le corriger explicitement.
5. **Test navigateur** des deux profils : compte joueur (`_isAdmin=false`) et
   compte dev. Les entrées `dev:true` ne doivent apparaître que pour le second.
6. **Rejouer les parcours** de la phase 1 et recompter les clics : le nombre
   doit avoir baissé là où c'était l'objectif, et n'avoir augmenté nulle part
   sans décision explicite.
7. `node scripts/sitemap.mjs` — la carte doit revenir avec **moins** d'entrées
   multiples et **zéro** retour incohérent nouveau.
8. Bump de version + entrée devlog (+ `DEVLOG_LATEST`), cf. `CLAUDE.md`.

## Phase 6 — Consigner

Comme pour `audit-audio`, **ce fichier ne s'améliore pas tout seul** : tout
défaut d'ergonomie trouvé une deuxième fois devient une règle numérotée
ci-dessous.

### Défauts déjà rencontrés (à ne plus reproduire)

1. **L'écran-péage** — `screen-menu` : une page entière pour deux boutons dont
   un seul (déconnexion) était unique. Coût : +1 clic sur tout ce qui passait
   derrière.
2. **Le doublon de refonte** — le Tuto laissé au Château après son
   déménagement au Dojo. Une refonte qui déplace doit *retirer*, pas rediriger.
3. **Le libellé fourre-tout** — « Options & paramètres » et « Identité »
   pointaient sur des choses qu'aucun joueur n'aurait cherchées là.
4. **Le retour contextuel oublié** — `showScreen('profile')` codé en dur dans
   un écran ouvert depuis le village : le joueur atterrit dans une branche
   qu'il n'a pas ouverte. `villageInterceptBack()` ne rattrape *que* les
   anciens hubs.
5. **Le bloc dupliqué** — le sélecteur de thème d'interface existait en deux
   exemplaires dans deux écrans sans rapport ; corriger l'un laissait l'autre
   faux.
6. **Le contrôle mort mais visible** — les joueurs n'ont plus qu'un thème,
   mais le sélecteur restait affiché. Retirer une fonctionnalité, c'est aussi
   retirer son bouton.
7. **Le libellé qui pointe vers un hub sans le contenu promis** — Archives
   « Série de connexion » routait vers `screen:'play'`, qui n'affichait
   AUCUNE série (le vrai widget vivait sur un écran inatteignable en thème
   village). Un item qui route vers un écran-hub partagé (play/menu/settings)
   doit être vérifié : le contenu promis par le libellé est-il vraiment
   VISIBLE sur cet écran, ou juste vaguement à proximité thématique ?
8. **Le titre à l'écran contredit le libellé du menu** — Archives « Journal
   d'activité » menait à une section titrée à l'écran « Journal des
   tournois », plus étroite que le contenu réel (comprend aussi connexions et
   PvP). Trois noms différents pour la même chose (menu / titre affiché /
   commentaire code) = signal d'alarme Q3 direct. Toujours lire le titre
   RENDU à l'écran, pas seulement le libellé du menu qui y mène.

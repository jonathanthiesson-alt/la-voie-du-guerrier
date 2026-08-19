---
name: lvdg-audit-audio
description: Audit complet du son de La Voie du Guerrier (musiques, SFX, déclencheurs, fuites). À lancer quand un son se déclenche au mauvais moment, ne part pas, ou se superpose.
---

# Audit audio — La Voie du Guerrier

> **Ce fichier ne s'améliore pas tout seul.** C'est NOUS qui l'enrichissons :
> **chaque bug audio trouvé DOIT devenir une règle ci-dessous**, sinon il
> reviendra. C'est la même mécanique que les pièges Supabase de `CLAUDE.md`,
> et c'est ce qui a fini par rendre ces pièges-là inoffensifs.
> Dernière passe : 2026-08-19.

## Pourquoi ce skill existe

Les bugs audio de ce projet sont **muets** : un `.catch()` avale l'erreur, un
`setTimeout` se déclenche sur le mauvais écran, une fonction en écrase une
autre. Rien n'apparaît dans la console, et le bug n'est visible qu'à l'oreille,
sur un écran précis, dans un ordre précis. D'où la nécessité d'une passe
systématique plutôt que d'un test au jugé.

## Inventaire (à revalider à chaque passe)

Éléments `<audio>` : `start-sfx`, `countdown-sfx`, `endgame-sfx`, `menu-music`,
`fight-music`.

Fonctions : `playSound`, `playStartSfx`, `playEndgameSfx`,
`cancelPendingEndgameSfx`, `startMenuMusic`/`stopMenuMusic`,
`startFightMusic`/`stopFightMusic`, `attemptPlayMusic`, `unlockAllAudio`.

## Les 6 règles (chacune vient d'un bug réel)

### 1. 🔴 Aucune fonction audio ne doit être définie deux fois
**Vécu (2026-07-17)** : `playSound` existait en double (l. 3694 et 15106). La
seconde écrasait la première — silencieusement. La version perdante portait le
`try/catch`, la gagnante le respect de `userPrefs.sound` : on avait donc perdu
la protection sans jamais le voir.

```bash
python -c "
import re
html=open('index.html',encoding='utf-8').read()
js='\n;\n'.join(re.findall(r'<script(?:\s[^>]*)?>(.*?)</script>',html,re.DOTALL))
for fn in ['playSound','playStartSfx','playEndgameSfx','cancelPendingEndgameSfx',
           'startMenuMusic','stopMenuMusic','startFightMusic','stopFightMusic',
           'attemptPlayMusic','unlockAllAudio']:
    n=js.count('function '+fn+'(')
    i=js.find('function '+fn+'(')
    d=js[:i].count('{')-js[:i].count('}') if i>=0 else -1
    print(fn, 'occurrences', n, 'profondeur', d, '' if (n==1 and d==0) else '<<<< PROBLEME')
"
```
Attendu : **occurrences 1, profondeur 0** partout.

### 2. 🔴 Tout son différé doit être annulable
**Vécu (2026-07-17)** : `playEndgameSfx()` programmait le son à +1,5 s sans
retenir le minuteur. Quitter l'écran dans ce délai → le son de fin de combat
se déclenchait **par-dessus le menu**. Symptôme signalé : « l'accès au menu
lance le son de fin de combat ».

Règle : tout `setTimeout` qui joue un son garde sa référence et est annulé
quand le contexte disparaît. Annuler le minuteur **ne suffit pas** : le son a
pu déjà démarrer → `pause()` + `currentTime = 0` aussi.
Point d'annulation unique : `showScreen()`, sur `id !== 'game'`.

### 3. 🔴 Ne jamais mettre en pause sur un `setTimeout` aveugle
**Vécu** : `unlockAllAudio()` jouait en muet puis coupait après 120 ms. Sur un
fichier pas encore tamponné, la lecture démarrait **après** la pause, `muted`
déjà restauré → le son partait en clair. Toujours attendre la **résolution de
la promesse** de `play()`.

### 4. 🔴 `.paused` passe à `false` dès l'appel de `play()`
…avant que le son ne soit audible. `startMenuMusic()` croyait donc la musique
déjà lancée et ne faisait rien. D'où `_menuMusicIntended` : on suit
**l'intention**, jamais l'état réel de l'élément.

### 5. 🔴 Le son ne doit jamais casser la chaîne d'un coup
`playSound()` reste sous `try/catch` : une exception y romprait
`executeDrop → switchTurn → scheduleAI` et figerait la partie, sans rien dire.

### 6. 🔴 Un `play()` différé est refusé sur mobile
Sans geste utilisateur direct, la promesse est rejetée en silence (notre
`.catch()` l'avale). C'est la raison d'être d'`unlockAllAudio()` et du
réessai au prochain geste dans `attemptPlayMusic()`.

### 7. 🔴 Démarrer une musique/un son doit vérifier l'écran COURANT, pas l'intention passée
**Vécu (2026-07-27)** : « des fois, une musique de combat se lance en arrivant
aux menus (après *Se connecter*) ». `startFightMusic()` n'est atteint que par des
chemins **différés** — `setTimeout` de démarrage, callback du décompte
« 3,2,1 Combattez », et un **polling "prêt" toutes les 500 ms**
(`markReadyAndWaitForOpponent`). Si l'écran changeait entre l'armement et le
déclenchement (match avorté, retour menu, reprise de session au login), l'appel
différé jouait la musique de combat **par-dessus le menu**. C'est le pendant de
la règle 2 pour une musique : un son différé doit re-vérifier son **contexte au
moment où il part**, pas se fier à un drapeau d'intention.

Règle : toute fonction qui **démarre** un son propre à un écran (fight-music =
écran de jeu) vérifie `document.querySelector('.screen.active').id` au tout
début et **sort sans rien faire** si on n'est pas sur le bon écran (sortir
AVANT `stopMenuMusic()`, sinon on coupe la musique du menu où l'on se trouve).
**Complément (2026-08-02) — la garde doit être sur la lecture IMMÉDIATE, pas
seulement le retry.** L'audit a montré que `attemptPlayMusic()` appelait
`el.play()` **immédiatement sans garde d'écran** ; seule la 2ᵉ tentative
différée vérifiait l'écran. Or l'**enchaînement sur `ended`** (fin naturelle
d'un morceau) rappelle `attemptPlayMusic('fight-music')` en ne testant que
`_fightMusicActive` → un morceau qui se terminait après un retour au menu
**relançait la musique de combat par-dessus le menu**. Correctif : la
vérification d'écran (`_fightMusicActive && userPrefs.fightMusic &&
'.screen.active'.id==='screen-game'`) est désormais **au tout début de
`attemptPlayMusic`**, donc **centrale** — elle couvre `startFightMusic`, le
retry, l'enchaînement `ended`, la reprise d'onglet, et tout futur appelant.
Contre-épreuve obligatoire : sur `screen-game`, la musique de combat DOIT
toujours partir (sinon on a supprimé au lieu de corriger). Test spécifique de
l'enchaînement : sur le menu, drapeau `_fightMusicActive` laissé à `true`,
`el.dispatchEvent(new Event('ended'))` → `plays === 0`.

### 8. 🔴 La musique de MENU aussi doit être gardée sur l'écran de jeu (symétrique de la 7)
**Vécu (2026-08-05)** : « une musique de combat se lance après *Commencer*, EN
PLUS de la musique du menu ». Le vrai fautif n'était pas la musique de combat
mais la musique de **menu** : `startMenuMusic()` (et `attemptPlayMusic` pour
`menu-music`) n'avait **aucune garde d'écran**. Un appel parasite pendant le
combat (reprise de session, chemin non gardé) jouait la musique de menu
**par-dessus** la musique de combat → les deux ensemble.

La règle 7 gardait `fight-music` hors des menus ; il manquait la **réciproque**.
Correctif : garde-fou central dans `attemptPlayMusic`, symétrique à celui de
fight-music — `menu-music` ne joue jamais si `.screen.active.id==='screen-game'`.
Central (pas seulement dans `startMenuMusic`) pour couvrir aussi le **retry
différé** et tout futur appelant.
Contre-épreuve obligatoire : sur `screen-menu`, la musique de menu DOIT toujours
partir (sinon on a supprimé au lieu de corriger) ; sur `screen-game`, un
`startMenuMusic()` parasite ne doit RIEN jouer alors que `fight-music` continue.

### 9. 🔴 Un NOUVEL écran d'accueil doit reprendre le même nettoyage que 'menu'/'home' — sinon les règles 7/8 ne le couvrent pas
**Vécu (2026-08-18)** : « musique de combat qui joue sur le menu village ».
Après un Combat rapide (matchmaking), le bouton « ↩ Retour » de l'overlay de
fin appelle `endgameToVillage()` → `villageMenuReturn()` → `showScreen
('village')`. L'écran `'village'` (thème Village, ajouté après les règles 7/8)
n'était couvert par AUCUN des points d'arrêt centralisés de `showScreen()` —
seuls `id==='menu'` et `id==='home'` coupaient `fight-music`/relançaient
`menu-music`. La musique de combat restait donc active indéfiniment sur la
carte du village.

Les règles 7/8 protègent contre un son qui *démarre* au mauvais endroit ; ce
bug est différent — un son qui *continue* faute d'un point de sortie sur un
écran qui n'existait pas quand ces règles ont été écrites. La règle 2 le
disait déjà : *« point d'annulation unique : `showScreen()` »* — encore
faut-il que TOUS les écrans « hub »/accueil y soient représentés, pas
seulement ceux qui existaient au moment du dernier audit.

Correctif : dans `showScreen()`, `if(id==='village'){ stopFightMusic();
startMenuMusic(); }` — même patron que `'menu'`.
**Réflexe à ajouter à la procédure (§ ci-dessous)** : avant de conclure,
lister TOUS les écrans qui peuvent servir de point d'arrivée après une
partie (grep `showScreen('` dans les fonctions de fin de partie/overlay :
`handleMenuClick`, `endgameToVillage`, `endgameNewCombat`, tout futur bouton
similaire) et vérifier que CHACUN de leurs écrans cibles a son propre
nettoyage dans `showScreen()` — pas seulement `'menu'` et `'home'`.

### 10. 🔴 Un ABANDON en pleine partie ne passe pas par `endGame()` — donc pas par son nettoyage audio non plus
**Vécu (2026-08-19, trouvé lors d'une passe d'audit générale, pas signalé
par un joueur)** : `quitOnlineGame(destScreen)` — le bouton « ✕ Quitter »
de la barre de partie en ligne — écrit `status='finished'` en base et
appelle `showScreen(destScreen)` **directement**, dans la branche « partie
encore en cours » (`!G.gameOver`). Cette branche ne passe **jamais** par
`endGame()`, qui est pourtant l'endroit qui coupe `fight-music` (dès sa 2e
ligne) et relance `menu-music` sur les écrans qui le prévoient. Résultat :
après un abandon volontaire, `fight-music` restait active indéfiniment, et
`menu-music` ne repartait pas non plus (silence total) — `destScreen` vaut
`'online-menu'` ou `'sumo'`, deux écrans que `showScreen()` ne couvre pas
(règle 9 ne couvre que les écrans-hub village/menu/home).

Différent de la règle 9 : là, c'était un écran d'arrivée manquant dans
`showScreen()`. Ici, c'est un **point de sortie qui contourne carrément
`endGame()`** — aucun nettoyage centralisé ne peut le rattraper puisqu'il
n'y passe pas. La règle 2 (« point d'annulation unique : `showScreen()` »)
a une exception implicite qu'il fallait documenter : un abandon AVANT la fin
naturelle d'une partie n'est pas un simple changement d'écran, c'est un
second chemin de sortie qui doit refaire lui-même ce que `endGame()` aurait
fait.

Correctif : `stopFightMusic()` + `startMenuMusic()` ajoutés directement
dans `quitOnlineGame()`, juste avant `showScreen(destScreen)` — à la
source, plutôt que d'énumérer tous les `destScreen` possibles présents et
futurs dans `showScreen()`.
**Réflexe supplémentaire pour la procédure** : chercher aussi les fonctions
qui écrivent `status='finished'`/appellent une RPC de forfait/abandon SANS
appeler `endGame()` derrière (`quitOnlineGame`, `invasion_forfeit` côté
client, tout futur bouton d'abandon) — ce sont des points de sortie
parallèles à `endGame()`, pas seulement des destinations d'écran.

## Matrice de test (navigateur, tabId de la Browser pane)

Espionner `play()` plutôt qu'écouter : on teste le **déclenchement**, sans
dépendre de l'autoplay.

```js
const sfx = document.getElementById('endgame-sfx');
let plays = 0; sfx.play = function(){ plays++; return Promise.resolve(); };
userPrefs.sound = true;
playEndgameSfx(false);
showScreen('menu');
await new Promise(r => setTimeout(r, 1800));
plays === 0; // doit être vrai
```

**Toujours faire la contre-épreuve** : rester sur l'écran de jeu doit donner
`plays === 1`. Un correctif qui supprime le son dans TOUS les cas passerait le
premier test — c'est le second qui prouve qu'on a corrigé au lieu de casser.

| Scénario | Attendu |
|---|---|
| Fin de partie, on reste | son de fin après ~1,5 s |
| Fin de partie → Menu en <1,5 s | **aucun** son de fin au menu |
| Menu, musique de menu OFF | aucune musique, aucun son de fin |
| Entrée en partie | musique de menu coupée |
| Décompte de combat | musique de combat (mobile inclus) |
| Réglage son OFF | rien nulle part |
| Retour à l'accueil | menu + combat coupés |
| `startFightMusic()` résolu hors écran de jeu (match avorté, login) | **aucune** musique de combat ; contre-épreuve sur `screen-game` = musique OK |
| `startMenuMusic()` parasite pendant le combat (sur `screen-game`) | **aucune** musique de menu ; contre-épreuve sur `screen-menu` = musique OK |
| Fin de Combat rapide → bouton « ↩ Retour » (`villageMenuReturn()`) | fight-music coupée, menu-music relancée, comme via `showScreen('menu')` |
| Abandon en pleine partie (`quitOnlineGame()`, bouton « ✕ Quitter ») | fight-music coupée, menu-music relancée, même si `destScreen` n'est ni menu/home/village |

## Procédure

1. Lancer le script de la règle 1 (doublons).
2. Chercher tout `setTimeout` proche d'un `play()` : chacun doit être annulable (règle 2).
3. **Lister tous les écrans d'arrivée possibles après une partie** (grep
   `showScreen('` dans les fonctions de fin/overlay : `handleMenuClick`,
   `endgameToVillage`, `endgameNewCombat`, tout futur bouton similaire) et
   vérifier que chacun a son propre nettoyage dans `showScreen()` — pas
   seulement `'menu'`/`'home'` (règle 9).
4. **Chercher les chemins d'ABANDON qui contournent `endGame()`**
   (`quitOnlineGame`, toute fonction qui écrit `status='finished'` ou
   appelle une RPC de forfait SANS appeler `endGame()` derrière) et
   vérifier qu'ils font eux-mêmes le nettoyage audio (règle 10).
5. Dérouler la matrice dans le navigateur, contre-épreuves comprises.
6. **Consigner tout nouveau bug ici en règle numérotée**, avec le symptôme
   observé — c'est le seul mécanisme d'amélioration de ce fichier.

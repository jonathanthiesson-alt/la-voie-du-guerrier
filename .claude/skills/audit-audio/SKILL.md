---
name: audit-audio
description: Audit complet du son de La Voie du Guerrier (musiques, SFX, déclencheurs, fuites). À lancer quand un son se déclenche au mauvais moment, ne part pas, ou se superpose.
---

# Audit audio — La Voie du Guerrier

> **Ce fichier ne s'améliore pas tout seul.** C'est NOUS qui l'enrichissons :
> **chaque bug audio trouvé DOIT devenir une règle ci-dessous**, sinon il
> reviendra. C'est la même mécanique que les pièges Supabase de `CLAUDE.md`,
> et c'est ce qui a fini par rendre ces pièges-là inoffensifs.
> Dernière passe : 2026-07-17.

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

## Procédure

1. Lancer le script de la règle 1 (doublons).
2. Chercher tout `setTimeout` proche d'un `play()` : chacun doit être annulable (règle 2).
3. Dérouler la matrice dans le navigateur, contre-épreuves comprises.
4. **Consigner tout nouveau bug ici en règle numérotée**, avec le symptôme
   observé — c'est le seul mécanisme d'amélioration de ce fichier.

---
name: lvdg-audit-vibration
description: Audit et correction automatique des vibrations (haptic) de La Voie du Guerrier — pourquoi ça s'arrête de marcher, où ça devrait vibrer et où ça ne le fait pas. À lancer quand un joueur signale « les vibrations ne marchent plus », après toute modification touchant executeDrop/switchTurn/endGame/applyRemoteGameState, ou pour un audit complet.
---

# Audit Vibration

> C'est un bug **récurrent** de ce projet (2ᵉ signalement le 2026-08-16,
> Wurmz : « c'est un problème récurrent de devoir réparer la vibration »).
> Ce fichier ne s'améliore pas tout seul : tout nouveau cas de vibration
> cassée ou manquante devient une règle numérotée en § Défauts déjà
> rencontrés, sinon il reviendra une 3ᵉ fois.

## Pourquoi la vibration casse souvent (contrairement au son)

`navigator.vibrate()` a des contraintes que `playSound()` n'a pas, ce qui la
rend plus fragile à chaque refonte du flux de jeu :

1. **Absente sur iOS Safari** — restriction permanente de WebKit, ce n'est
   PAS un bug de l'app. Sur iOS, `haptic()` ne fera jamais rien tant que le
   jeu n'est pas empaqueté avec le plugin natif `@capacitor/haptics`
   (AXE 5, portage). Sur Android/Chrome ça fonctionne normalement.
2. **Activation « collante » liée au geste utilisateur** — certains
   navigateurs (Chrome Android en tête) exigent que `vibrate()` soit appelé
   dans la foulée d'une interaction utilisateur récente (tap, clic). Un
   appel déclenché depuis un `setTimeout` trop éloigné du geste, ou depuis un
   callback purement réseau (retour Realtime, réponse Supabase), peut être
   silencieusement ignoré selon le navigateur.
3. **Durées historiquement trop courtes** — le bug déjà corrigé une fois
   (voir § défauts) : 5/10/15 ms sont sous le seuil perceptible de la
   plupart des moteurs Android. Toute nouvelle entrée dans la table `p` de
   `haptic()` doit rester ≥ 15 ms.
4. **Chaque refonte de flux de jeu peut faire disparaître un point d'appel**
   sans erreur JS — `haptic()` ne lève jamais, un appel oublié après un
   `switchTurn()`/`endGame()` réécrit ne casse RIEN visiblement, sauf le
   silence sur le téléphone.

## Cartographie des points d'appel (à revalider à chaque passe)

```bash
grep -n "haptic(" index.html
```

| Déclencheur attendu | Fonction porteuse | Type d'appel |
|---|---|---|
| Tap sur un bouton de l'UI | listener délégué `touchstart` | `tap` |
| Sélection/déplacement d'une pièce | `executeDrop` / `onDragEnd` | `select` |
| Poussée | `execMove` (branches push) | `push` |
| Capture | `execMove` (branches capture) | `capture` |
| Victoire / défaite | `endGame` | `victory` / `defeat` |
| **« À moi de jouer » (local/vsAI)** | `switchTurn()`, uniquement quand `G.turn===G.bottomColor` et `!G.onlineGameId` | `select` |
| **« À moi de jouer » (en ligne)** | `applyRemoteGameState()`, sur réception du coup adverse | `move` |
| **Alerte 3 secondes du minuteur** | `fireTimerTickAlert()` (appelée depuis `startTurnTimer`), gardée par `userPrefs.tickWarnVibrate` | `tap` |
| Décompte de combat 5-4-3-2-1 | `runCombatCountdown()` | `select` |

Si un de ces déclencheurs ne vibre plus, chercher en premier lequel des
points de cette table a disparu ou est devenu inatteignable (garde ajoutée
par erreur, fonction renommée, branche retirée).

## Procédure

### Phase 1 — Vérifier que `haptic()` elle-même est saine

```bash
python3 -c "
import re
html=open('index.html',encoding='utf-8').read()
js='\n;\n'.join(re.findall(r'<script(?:\s[^>]*)?>(.*?)</script>',html,re.DOTALL))
i=js.find('function haptic(')
n=js.count('function haptic(')
d=js[:i].count('{')-js[:i].count('}') if i>=0 else -1
print('occurrences', n, 'profondeur', d, '' if (n==1 and d==0) else '<<<< PROBLEME')
"
```
Attendu : occurrences 1, profondeur 0 (sinon c'est le piège classique
`CLAUDE.md` — fonction imbriquée invisible depuis le reste du code).

Vérifier aussi :
- `userPrefs.haptic` existe et vaut `true` par défaut dans la définition de
  `userPrefs` (sinon la case Réglages > Vibrations part décochée pour tout
  nouveau joueur, silencieusement).
- Toutes les durées de la table `p` dans `haptic()` sont ≥ 15 ms (règle 3
  ci-dessus).
- Le toggle Réglages (`toggleSetting('haptic')`) déclenche bien un
  `haptic('capture')` de test à l'activation — c'est le seul moyen pour le
  joueur de savoir immédiatement si son appareil vibre réellement.

### Phase 2 — Revalider chaque point d'appel de la cartographie

Pour chacune des lignes du tableau : grep le nom de fonction porteuse,
lire son code, confirmer que l'appel `haptic(...)` y est toujours présent
et **atteignable** (pas dans une branche `if` qui `return` avant, pas
retirée par une refonte récente). Croiser avec `git log -p -- index.html`
sur les fonctions listées si un signalement pointe vers un cas précis.

### Phase 3 — Test navigateur (Chrome Android réel ou émulateur — Safari
iOS ne testera jamais rien, cf. § pourquoi ça casse)

Espionner `navigator.vibrate` plutôt que de compter sur la perception :

```js
let calls = [];
navigator.vibrate = function(p){ calls.push(p); return true; };
```

Puis dérouler la matrice :

| Scénario | Attendu |
|---|---|
| Coup joué (poussée) | 1 appel `[40]` |
| Coup joué (capture) | 1 appel `[45,25,45]` |
| Partie locale vsAI, l'IA vient de jouer, tour revient au joueur du bas | 1 appel `[20]` (`select`) |
| Partie en ligne, l'adversaire vient de jouer | 1 appel `[25]` (`move`) |
| Minuteur descend à 3s, case cadence cochée | 1 appel `[15]` (`tap`) |
| Minuteur descend à 3s, case cadence DÉCOCHÉE | 0 appel |
| Réglages > Vibrations décoché | 0 appel sur TOUS les scénarios ci-dessus |
| Fin de partie (victoire/défaite) | 1 appel `victory`/`defeat` |

### Phase 4 — Consigner

Tout nouveau cas de vibration cassée ou manquante devient une règle
numérotée ci-dessous, avec le symptôme observé et la cause réelle (pas
juste « corrigé »).

### Défauts déjà rencontrés (à ne plus reproduire)

1. **Durées sous le seuil perceptible** — les valeurs historiques
   (5/10/15 ms) étaient trop courtes pour la plupart des moteurs de
   vibration Android, d'où l'impression que « ça n'a jamais marché ».
   Revues à la hausse (≥ 15 ms).
2. **« À moi de jouer » jamais câblé en local/vsAI** — le chemin en ligne
   vibrait déjà à la réception du coup adverse (`applyRemoteGameState`),
   mais `switchTurn()` (parties locales et vsAI) ne vibrait jamais quand le
   tour revenait au joueur — silence total sur la majorité des parties
   jouées (Karakuri, Adversaires, hotseat). Corrigé le 2026-08-16 : appel
   `haptic('select')` ajouté dans `switchTurn()`, gardé par
   `G.turn===G.bottomColor && !G.onlineGameId` pour ne pas dupliquer le
   chemin en ligne.

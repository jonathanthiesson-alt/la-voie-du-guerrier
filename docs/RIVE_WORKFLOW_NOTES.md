# Rive — Carnet de bord & recette de riggage (à reprendre avec Thomas)

> **Statut : exploration en pause (2026-08-02).** On a **validé le process complet**
> de riggage d'un samouraï dans Rive, sur un squelette à notre convention. On
> reprendra ici pour finaliser (proportions → gel → animations → export → test).
> Ce doc = ce qu'on montre à Thomas + la recette reproductible.
>
> Docs liés : `RIVE_PHASE0_BRIEF.md` (squelette théorique), `RIVE_DEFAULT_SKINS_SPEC.md`
> (2 skins Blanc/Noir), `ANIMATIONS_CATALOGUE.md` (les clips), `FX_MANGA_BRIEF.md` (FX).

---

## 1. Où on en est (fait ✅ / à faire ⬜)

- ✅ Rive installé, prise en main de l'éditeur (BETA 0.8.x).
- ✅ Découverte d'un asset de référence **CC BY 4.0** (voir §5 attribution).
- ✅ Décision : partir d'un **SVG maison généré (Gemini)**, découpé en pièces
  nommées → plus propre et sans souci de droits que remixer l'asset.
- ✅ **Riggage validé** : squelette complet à notre convention + pièces accrochées
  + **test de rotation OK** (bras/jambe/torse propagent correctement).
- ⬜ **Finaliser les proportions** (dernier moment « pas cher » avant de figer).
- ⬜ **Geler le squelette.**
- ⬜ **Animer** : idle, strike, poussées… (cf. `ANIMATIONS_CATALOGUE.md`).
- ⬜ **State machine `combat`** (inputs `toStrike`, `toReflexion`, `impact`).
- ⬜ **Exporter `.riv`** et **tester dans `avatars/rive/skins-test.html`**.
- ⬜ **Recolorier** pour le combattant Noir (sabre bleu, obi bleu…).
- ⬜ **Intégrer** au bandeau via `triggerCombatAnim` (remplace `ProtoBanner`).

**Fichier source du perso :** `C:\Users\ameli\OneDrive\Bureau\voie de la lame\RIVE INPUTS\gemini-svg.svg`
(SVG 800×800, groupe racine `Samurai_Character`, pièces déjà séparées et nommées).

---

## 2. 🔑 La recette de riggage validée (reproductible)

C'est LE mode d'emploi pour riguer n'importe quel perso maison dans Rive.

1. **Préparer le dessin** : un **SVG découpé en pièces**, **un calque/groupe par
   partie du corps**, bien **nommé** (torse, bras haut/bas, main, cuisse, mollet,
   pied, tête, arme…). ⚠️ Un PNG plat ou un SVG non découpé = **non riguable**.
2. **Importer** dans Rive (glisser-déposer / panneau *Assets*). Le SVG arrive
   **sans os** (normal, un SVG n'a pas de squelette).
3. **Créer le squelette** avec l'outil **Bone**, à notre convention :
   - Colonne : `root` (bassin) → `spine` → `chest` → `head`.
   - Bras (partent de **`chest`**) : `shoulderR → elbowR → handR → osArme` ;
     `shoulderL → elbowL → handL`.
   - Jambes (partent de **`root`**) : `hipR → kneeR → footR` ; `hipL → kneeL → footL`.
   - ⚠️ **Re-sélectionner l'os parent** (`chest` ou `root`) **avant** de tracer
     chaque nouvelle chaîne, sinon elle part du dernier os dessiné.
4. **Vérifier la hiérarchie** : un os doit être **enfant de l'os qu'il suit**
   (les bras **sous `chest`**, pas au niveau de `root`). Corriger par
   **glisser-déposer** dans la Hierarchy (Rive garde la position visuelle).
5. **Accrocher les pièces** (parentage rigide) : **glisser chaque groupe de
   dessin sur son os**. Pas de mesh à peindre — les pièces étant séparées, le
   parentage rigide suffit. Table de correspondance dans `RIVE_DEFAULT_SKINS_SPEC.md`.
   - ⚠️ Ne pas oublier **`Katana_Group` → `osArme`** (sinon la lame ne suit pas).
   - Supprimer les **groupes wrappers vides** une fois leurs pièces sorties.
6. **Tester** : faire **pivoter** `elbowR`, `hipR`, `chest` → tout le membre doit
   suivre, puis **Ctrl+Z**. Si oui → **rig validé**.

---

## 3. Décisions & apprentissages (cette session)

- 🔴 **Pas d'IA « image → rig » fiable.** Aucun outil ne sort un `.riv` riggé
  propre depuis une image plate ; les auto-rig inventent leur squelette et
  **cassent la règle d'or**. Confirme notre choix « pas d'auto-génération ».
- 🔴 **Le SVG DOIT être découpé en pièces nommées** en amont (c'est là que
  Gemini/Illustrator aide : générer/séparer les calques). Le riggage lui-même
  reste **100 % manuel** (et rapide, une fois le dessin propre).
- 🟢 **Parentage rigide** (glisser la pièce sur l'os) suffit pour des pièces
  plates séparées → pas besoin de skinning/mesh pour la V1.
- 🟢 **Pas besoin de renommer les os pour le jeu** : le runtime pilote la
  **state machine** (inputs), jamais les os. Mais nommer à notre convention
  **facilite le riggage et les anims** — on le fait quand même.
- 🔴 **Ordre impératif** : proportions **d'abord**, **geler** le squelette,
  **animer** ensuite. Retoucher les proportions après avoir animé décale tout.
- 🟢 Le **model sheet** (poses garde/lever/fente/coup horizontal) sert de
  **référence d'animation** pour les clips de combat.

---

## 4. Reprise avec Thomas — checklist

1. Rouvrir le fichier Rive du samouraï (rig déjà validé).
2. **Proportions** : ajuster tête/torse/membres à la DA voulue (mode Design,
   déplacer les os → l'art suit). Valider ensemble.
3. **Geler** (ne plus toucher aux os).
4. **Animer** les clips du `ANIMATIONS_CATALOGUE.md` (commencer par `idle`,
   `reflexion`, `strike`), sur la timeline (mode Animate).
5. **State machine `combat`** : états `idle`/`reflexion`/`strike`, inputs
   `toReflexion`/`toStrike`/`impact` (trigger FX posé vide).
6. **Export** `default-skins.riv` → `avatars/rive/` → test `skins-test.html`.
7. **Recolorier** en dupliquant l'artboard → variante Noir.
8. **Brancher** au jeu : remplacer le moteur `ProtoBanner` au point d'accroche
   `triggerCombatAnim(key, moverColor)` — les 8+4 clés mappent la state machine.

---

## 5. ⚖️ Droits / attribution

- Asset de référence vu dans le marketplace Rive : **« Samurai Drum Hero Slider »**,
  auteur **novacraftcreatives**, **gratuit, CC BY 4.0** (réutilisable/remixable
  **avec attribution**). Si on réutilise **quoi que ce soit** issu de cet asset,
  on garde le crédit « d'après novacraftcreatives, CC BY 4.0 » (devlog + écran
  crédits + fichier `NOTICE`).
- Le perso qu'on rigue actuellement vient d'un **SVG généré maison (Gemini)** →
  pas de dépendance à l'asset CC BY pour l'instant. Vérifier au moment d'intégrer
  s'il reste une part de l'asset CC BY (→ attribution) ou non (→ rien à faire).

*Carnet ouvert le 2026-08-02. À compléter à chaque session Rive.*

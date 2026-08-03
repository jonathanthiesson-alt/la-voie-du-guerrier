# L'équipe des 15 — roster, noms & sens

> **Statut : SPEC (Phase A non construite).** Ce document fige les 16 profils
> d'IA-bots nommés, leur ordre de force, les règles de déblocage de la galerie
> et — nouveauté demandée le 2026-08-03 — **le sens de chaque nom, à afficher
> dans le profil du bot**. Le reste du plan (backfill, tournois, carrousel) est
> dans [[armee-de-bots]] (mémoire) et `docs/BOT_ARMY_PLAN.md`.

---

## Principe des noms

Chaque bot porte le patron **`NN-Nombre-Rang`** :

- **`NN`** = le numéro à deux chiffres (00 à 15).
- **`Nombre`** = ce numéro **dit en japonais** (rei, ichi, ni…).
- **`Rang`** = un **archétype guerrier** japonais, du plus humble au plus haut.

Les deux bornes portent tout le sens :

- **15 · Bushi** (武士, « le guerrier ») est le sommet **visible** : c'est
  l'incarnation même de la **Voie du Guerrier** (*bushidō*). Pinacle des numéros.
- **00 · Rōnin** (浪人, « l'homme-vague », samouraï **sans maître**) est
  au-**delà** des rangs : le boss caché « qui n'existe pas ». *Rei* (零) veut dire
  **zéro / le néant** — le vide d'où il surgit.

Le rang n'est **pas** un classement de force strict (la force suit le numéro,
voir plus bas) : c'est de la **couleur**. Mais l'échelle monte globalement du
piétaille au seigneur, pour que la galerie « raconte » une ascension.

---

## Ordre de force

**1 < 2 < 3 < … < 14 < 15 < 0.** Le 0 est le plus fort ; le 1 le plus faible.
La force est ∝ à la profondeur d'analyse minimax du bot (à câbler en Phase A).
On rencontre un bot selon **l'Elo du joueur** (adversaire d'Elo proche).

## Déblocage de la galerie

- **1 → 10** : visibles et accessibles d'emblée.
- **11 → 15** : **grisés** tant qu'on ne les a pas **rencontrés** en partie.
  Clic sur un grisé → « Disponible une fois le personnage rencontré. »
- **0** : **n'apparaît même pas** dans la galerie ; il se **révèle** à la
  première rencontre.
- Nécessite de **tracker « bots rencontrés » par joueur** (table/colonne).

---

## Le roster (nom, lecture, sens)

> **À afficher dans le profil de chaque bot** : le kanji du nombre, sa lecture,
> le sens du rang, et la petite phrase de lore. `0` et `15` méritent la note
> thématique (bushidō / rōnin).

| # | Nom | Nombre (kanji · lecture) | Rang (kanji) | Sens du rang | Lore court |
|---|---|---|---|---|---|
| 01 | **Ichi-Ashigaru** | 一 · *ichi* (un) | 足軽 *ashigaru* | Fantassin, la piétaille | Le premier pas sur la Voie. Tout le monde a commencé ici. |
| 02 | **Ni-Genin** | 二 · *ni* (deux) | 下忍 *genin* | L'apprenti, rang le plus bas | Encore dans l'ombre, mais il apprend vite. |
| 03 | **San-Dōshin** | 三 · *san* (trois) | 同心 *dōshin* | Le garde, petit officier | Il tient son poste. On ne passe pas si facilement. |
| 04 | **Shi-Yōjimbo** | 四 · *shi* (quatre) | 用心棒 *yōjimbo* | Le garde du corps | *Shi* (四) sonne comme « mort » (死) : un numéro qu'on évite… lui non. |
| 05 | **Go-Musha** | 五 · *go* (cinq) | 武者 *musha* | Le guerrier aguerri | La moitié du chemin. Il a déjà vu des batailles. |
| 06 | **Roku-Kenshi** | 六 · *roku* (six) | 剣士 *kenshi* | L'escrimeur, sabre en main | Sa lame parle avant lui. |
| 07 | **Shichi-Bugeisha** | 七 · *shichi* (sept) | 武芸者 *bugeisha* | Le maître d'armes | Sept, chiffre de chance : la sienne, il la forge. |
| 08 | **Hachi-Samurai** | 八 · *hachi* (huit) | 侍 *samurai* | Le samouraï au service | *Hachi* (八) évoque la prospérité : un serviteur accompli. |
| 09 | **Kyū-Hatamoto** | 九 · *kyū* (neuf) | 旗本 *hatamoto* | Le vassal direct du shogun | Neuf, tout près du sommet. Il porte la bannière. |
| 10 | **Jū-Karō** | 十 · *jū* (dix) | 家老 *karō* | L'intendant, plus haut vassal | Dix : la main droite du seigneur. Dernier des « accessibles ». |
| 11 | **Jūichi-Kensei** | 十一 · *jūichi* (onze) | 剣聖 *kensei* | Le **saint du sabre** | *(grisé)* On ne le voit qu'après l'avoir croisé. Sa maîtrise est un mythe. |
| 12 | **Jūni-Daimyō** | 十二 · *jūni* (douze) | 大名 *daimyō* | Le grand seigneur féodal | *(grisé)* Il commande des provinces entières. |
| 13 | **Jūsan-Shōgun** | 十三 · *jūsan* (treize) | 将軍 *shōgun* | Le généralissime | *(grisé)* Treize : le chiffre qui fait trembler. Il règne. |
| 14 | **Jūyon-Kami** | 十四 · *jūyon* (quatorze) | 神 *kami* | La divinité, l'esprit tutélaire | *(grisé)* Plus tout à fait humain. On le vénère autant qu'on le craint. |
| 15 | **Jūgo-Bushi** | 十五 · *jūgo* (quinze) | 武士 *bushi* | **Le Guerrier** (bushidō) | *(grisé)* Sommet des numéros : l'incarnation même de la Voie. |
| 00 | **Rei-Rōnin** | 零 · *rei* (zéro / néant) | 浪人 *rōnin* | Le samouraï **sans maître** | *(caché)* Le numéro qui n'existe pas. Surgi du vide, il ne répond à personne — et il est le plus fort. |

---

## Ce que le profil affiche (Phase A)

Pour chaque bot, la fiche montre : visuel, **Elo**, statut « toujours en ligne »,
et un encart **« Le sens du nom »** reprenant la colonne *Sens* + *Lore* + le
kanji du nombre. Les grisés (11-15) n'exposent ce texte **qu'après rencontre** ;
le 0 idem, et il reste absent de la galerie jusque-là.

*Spec rédigée le 2026-08-03. Force ∝ profondeur minimax (à câbler). Voir
[[armee-de-bots]] pour le backfill, les tournois et le carrousel.*

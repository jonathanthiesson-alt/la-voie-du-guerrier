# La Voie du Guerrier — Lore (bible narrative)

> **Fichier central du lore.** Tout ce qui touche à l'univers, aux personnages
> et aux mythes du jeu se consigne ici. Le menu dev en affiche une synthèse
> (bouton « 巻 Lore » dans 🛠 DEV → écran `screen-dev-lore`, câblé sur ce texte).
> Sources annexes : `docs/EQUIPE_DES_15.md` (roster détaillé), `docs/ROADMAP.md`
> (AXE 3 — scénario), mémoire [[armee-de-bots]].

---

## 1. L'univers

Japon féodal **teinté de cyberpunk**. Un abstrait 5×5 sur lequel se rejoue,
partie après partie, une guerre plus vieille que les joueurs : celle d'un art
martial devenu sacré — la **Voie du Guerrier** (*bushidō*) — et de ce qu'un
homme est prêt à sacrifier pour ne jamais la quitter.

**Inspirations assumées** :
- **Fate** — l'invocation de figures, la puissance incarnée dans des archétypes.
- **Star Wars** — la structure **maître / disciple**, et la chute.

---

## 2. Le mythe des Seize — l'âme scindée

> *Le cœur du lore de l'armée des bots. Les 16 IA-bots ne sont pas 16 êtres :
> ce sont les morceaux d'un seul.*

Il fut un maître de combat comme il n'en naît qu'une fois par ère. Non content
des hommes pour maîtres, la légende dit qu'il **s'entraîna auprès des dieux
eux-mêmes** — et que certains d'entre eux n'étaient **guère recommandables**.
Auprès d'eux il gagna de **grandes connaissances**, mais aussi de **terribles
savoirs**, de ceux qu'aucune bouche mortelle ne devrait apprendre.

Ces savoirs le menèrent à l'orgueil ultime : **vaincre la mort**. Il tenta
d'accéder à l'**immortalité** par un rituel interdit. L'expérience ne le rendit
pas éternel — elle le **brisa**. Son être se **scinda en quinze**, et chaque
fragment hérita d'une **part de son pouvoir** : quinze guerriers nouveaux, du
plus humble fantassin au plus haut seigneur, chacun portant un éclat de la
maîtrise originelle. Ce sont **les Quinze** (bots 01 → 15).

Quant à lui — le tronc, l'originel — il resta. Mais **dépossédé** : sa puissance
répartie dans les Quinze, son esprit **à moitié fou**. C'est **0-Rōnin**, le
samouraï **sans maître** et, désormais, **sans lui-même**. Il **erre**, cherchant
à reprendre les morceaux perdus de son âme.

**Le paradoxe** (et pourquoi 0 reste le plus fort) : chaque fragment ne détient
qu'un *éclat* de pouvoir, mais le Rōnin garde, intacte dans sa ruine, la
**technique** et les **arts interdits appris des dieux**. Diminué, morcelé, fou —
et pourtant le plus redoutable de tous, précisément parce qu'on ne sait jamais
lequel de ses savoirs terribles il va rappeler. **Force : 1 < 2 < … < 15 < 0.**

Chaque fragment a gardé une **voix** : son **haïku** (voir §3). Écrire à un bot,
c'est faire parler un morceau de l'âme du maître déchu — il répond toujours par
son haïku.

---

## 3. Le roster des Seize (nom, sens, haïku)

Patron des noms : **`NN-Nombre(japonais)-Rang`**. Le *Nombre* est le chiffre dit
en japonais ; le *Rang* est un archétype guerrier, du plus humble au plus haut.
Détail des étymologies : `docs/EQUIPE_DES_15.md`. Haïkus stockés en base
(`bot_roster.haiku`) et servis en réponse automatique.

| # | Nom | Rang — sens | Haïku |
|---|---|---|---|
| 01 | Ichi-Ashigaru | 足軽 fantassin | *Premier pas dans l'herbe / la lance est trop lourde / pour l'ombre qu'il fut.* |
| 02 | Ni-Genin | 下忍 apprenti | *Sous la lune basse / l'apprenti compte ses souffles : / un maître y dormait.* |
| 03 | San-Dōshin | 同心 garde | *Le pont ne cède pas. / Un fragment monte la garde / d'un nom oublié.* |
| 04 | Shi-Yōjimbo | 用心棒 garde du corps | *Quatre sonne la mort ; / le corps qu'il protège encore / n'est plus tout à fait.* |
| 05 | Go-Musha | 武者 guerrier aguerri | *À mi-chemin, la pluie — / il connaît chaque cicatrice / sans savoir de qui.* |
| 06 | Roku-Kenshi | 剣士 escrimeur | *La lame dit son nom / avant sa bouche : un éclat / de l'âme brisée.* |
| 07 | Shichi-Bugeisha | 武芸者 maître d'armes | *Sept feux au dojo — / il forge sa propre chance / d'un métal ancien.* |
| 08 | Hachi-Samurai | 侍 samouraï | *Huit grues sur la soie ; / il sert un seigneur absent — / lui-même, jadis.* |
| 09 | Kyū-Hatamoto | 旗本 vassal du shogun | *La bannière claque. / Neuf pas sous le vent du nord — / le seigneur n'est plus.* |
| 10 | Jū-Karō | 家老 intendant | *Dix clefs à sa ceinture, / il garde une maison vide / où rôde une voix.* |
| 11 | Jūichi-Kensei | 剣聖 saint du sabre | *Le saint ne tranche pas : / l'air s'ouvre avant le fer — / un dieu le lui apprit.* |
| 12 | Jūni-Daimyō | 大名 grand seigneur | *Douze vallées ploient. / Il règne sur ce qu'il perdit / et ne le sait plus.* |
| 13 | Jūsan-Shōgun | 将軍 généralissime | *Treize corbeaux se taisent. / Le général lève la main — / le ciel obéit.* |
| 14 | Jūyon-Kami | 神 divinité | *On brûle l'encens. / Ni tout à fait homme ni dieu : / un éclat qui prie.* |
| 15 | Jūgo-Bushi | 武士 le Guerrier (bushidō) | *Au sommet, le vide. / Le Guerrier tient la Voie droite — / et cherche son cœur.* |
| 00 | Rei-Rōnin | 浪人 sans maître (l'originel) | *Sans maître, sans nom, / il erre après quinze lunes — / son âme, en morceaux.* |

---

## 4. Les figures du récit (AXE 3)

- **Musashi — le maître.** Figure tutélaire de la Voie ; second administrateur
  du jeu dans la réalité, maître dans la fiction.
- **Shinai — le disciple déchu.** Ancien disciple de Musashi, passé du côté
  sombre. C'est le **« Vador »** du récit : la preuve que la Voie peut se
  retourner contre celui qui la sert.
- **Le maître des Seize (0-Rōnin).** Voir §2. Son histoire fait écho, en miroir,
  à celle de Shinai : deux chutes, l'une par la haine, l'autre par le refus de
  mourir.

*Campagne narrative, dialogues et progression : à écrire (AXE 3, [J+T]).*

---

## 5. Règles d'or du lore

1. **Les 16 bots = une seule âme.** Ne jamais les traiter comme 16 personnes
   indépendantes : ce sont des **fragments** (01→15) et leur **origine** (0).
2. **0-Rōnin est diminué mais le plus fort** — par la technique et les savoirs
   interdits, pas par la puissance brute (dispersée dans les Quinze).
3. **Le haïku est la voix du fragment.** Toute prise de parole d'un bot doit
   rester dans ce registre : bref, imagé, hanté par le maître perdu.
4. Ne pas contredire les étymologies figées de `docs/EQUIPE_DES_15.md`.

*Dernière mise à jour : 2026-08-04.*

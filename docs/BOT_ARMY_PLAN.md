# Armée de bots — plan de test online solo

> **But :** depuis le menu dev, **déployer/arrêter jusqu'à ~100 bots** qui se
> comportent comme de vrais joueurs en ligne, pour tester le online **seul** :
> matchmaking, arènes, tournois — avec un **rapport par mode**. Les bots doivent
> **rejoindre TA partie/arène/tournoi**.
>
> **Décisions (2026-08-02, Wurmz) :** comptes bots = **auth anonyme** ;
> exécution = **worker serveur** (GitHub Actions), comme le worker d'équilibre.
> Statut : **plan validé, build à venir** (dépend de ta machine + config Supabase).

---

## 1. Principe (calqué sur le worker d'équilibre)

Un bot = **une session Supabase authentifiée (anonyme)** + **ton IA existante**
(`allMoves` / `minimaxPlay`) + **tes chemins online existants** (RPC de coup,
`applyRemoteGameState`). On **réutilise le moteur extrait de `index.html`**
(pattern `labExtractBody`, déjà éprouvé, « copie exacte, zéro dérive »).

Contrainte clé : pour que les bots **existent** pour ton matchmaking/arène/tournoi,
ils doivent être de **vrais joueurs Supabase** → l'auth anonyme les provisionne à
la volée (une ligne `profiles` par bot, flag `is_bot=true`).

```
Menu dev (toi) ──écrit directive──▶ table bot_army_control ◀──lit── Worker GH Actions
      ▲                                                                    │
      └──────────── lit ──── table bot_army_report ◀──── écrit ───────────┘
                                                                           │
                                       N sessions anonymes (bots) ─────────┘
                                       chacune : IA + RPC online + is_bot
```

## 2. Composants à construire

### 2a. Fondation SQL (`sql_a_executer/dev_bot_army.sql`) — *toi tu l'exécutes*
- `profiles.is_bot boolean default false` (+ index).
- **Exclusion des classements** : patcher les vues/RPC de ligue, ELO, arène,
  tournoi, « joueurs en ligne » pour **filtrer `is_bot`** (les bots ne polluent
  jamais les stats/récompenses réelles). *(À cartographier au build : lister tous
  les points de classement.)*
- `bot_army_control` : ligne unique `{ enabled, count, mode, target_id, updated_by, updated_at }`
  — écrite par un **RPC admin** `bot_army_set_directive(...)` (vérifie `is_admin_user()`).
- `bot_army_report` : agrégats par mode écrits par le worker ; lus par le menu dev.
- **Nettoyage** : RPC admin `bot_army_purge()` (supprime bots + leurs parties/
  inscriptions) — indispensable pour ne pas laisser de comptes fantômes.

### 2b. Menu dev (dans `index.html`) — *je le construis, gaté `isDevUser()`*
- Bouton **Déployer / Arrêter** (écrit la directive via `bot_army_set_directive`).
- **Nombre de bots** (1–100) + **mode à tester** (matchmaking / arène / tournoi /
  « joueurs libres »).
- **Cible** : id de TON arène/tournoi en cours (pour que les bots viennent t'y rejoindre).
- **Rapport en direct par mode** (lit `bot_army_report`) : parties jouées,
  victoires/défaites, erreurs, latence, bots actifs.
- Bouton **Purger les bots**.

### 2c. Worker (`scripts/bot-army.mjs` + `.github/workflows/bot-army.yml`) — *je l'écris, tu le commit + il tourne*
- Workflow calqué sur `balance-worker.yml` : **cron court** (ex. toutes les 5 min
  pour capter un « start ») **+ `workflow_dispatch`** ; réutilise le secret
  **`SUPABASE_SERVICE_ROLE_KEY` déjà en place** (pour lire la directive, poser
  `is_bot`, purger — tâches admin), et l'**anon key publique** pour les sessions bots.
- Job **long** (jusqu'au `timeout-minutes`) qui, tant que `enabled` :
  - maintient jusqu'à `count` **sessions anonymes**,
  - chaque bot agit selon `mode` (voir §3), joue via l'IA à un **rythme réaliste**,
  - écrit son activité dans `bot_army_report`,
  - s'arrête proprement dès que la directive passe à `enabled=false`.

## 3. Comportement par mode

| Mode | Ce que font les bots |
|---|---|
| **Matchmaking** | se mettent « en ligne », s'apparient (entre eux **et avec toi** quand tu lances une recherche), jouent une partie via l'IA, recommencent |
| **Arène** | rejoignent l'**arène cible** (celle que tu as créée/rejointe), enchaînent les manches |
| **Tournoi** | s'**inscrivent** au tournoi cible, jouent leur **appariement** à chaque manche |
| **Joueurs libres** | présence continue + comportement varié → tester l'app « peuplée » (listes, compteurs en ligne, chat…) |

« Comme de vrais joueurs » = IA avec **diversité d'ouverture** + **temps de
réflexion** simulé, jamais instantané, pour un trafic crédible.

## 4. Pré-requis (toi, une fois)
1. **Activer l'auth anonyme** dans Supabase (Auth → Providers → Anonymous).
2. Exécuter `sql_a_executer/dev_bot_army.sql` (voir ordre dans `docs/SQL_MIGRATIONS.md`).
3. Commit le workflow + `scripts/bot-army.mjs`, vérifier qu'il apparaît dans Actions.
   *(Le secret `SUPABASE_SERVICE_ROLE_KEY` est déjà configuré — rien à ajouter.)*

Rappel : **je ne lance pas les migrations et je ne touche jamais la service key** —
j'écris tout, tu exécutes/actives.

## 5. Questions à trancher au build (je les résous en explorant le code)
- Modèle exact du **matchmaking** (liste « Jouer en ligne » = défi/acceptation, ou
  appariement auto ?) → détermine comment un bot « se fait matcher avec toi ».
- **RPC de jointure** arène/tournoi (noms/signatures) + comment cibler les tiens.
- **RLS + anon** : les RPC de partie/arène/tournoi acceptent-ils un utilisateur
  **anonyme** ? (certaines policies peuvent exiger des champs de profil).
- **Présence** : comment « en ligne » est calculé (heartbeat `last_seen` ?) pour
  que les bots apparaissent dispo.
- Limites free-tier (auth users, connexions, lignes) → **cap à 50** d'abord, 100 ensuite.

## 6. Ordre de build proposé
1. **Fondation SQL** (is_bot, control, report, RPC admin, purge, exclusion classements).
2. **Menu dev** (déployer/arrêter, count, mode, cible, rapport, purge).
3. **Worker + workflow** (sessions anonymes + IA + RPC online + report).
4. **Comportements par mode** (matchmaking → arène → tournoi), itératif avec test réel.
5. Réglages charge (cap, rythme) + purge/rollback.

*Plan rédigé le 2026-08-02. Réutilise le pattern worker d'équilibre
(`balance-worker.yml` / `scripts/balance-worker.mjs` / `dev_worker_config`).*

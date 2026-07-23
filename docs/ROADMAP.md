# Roadmap — les 6 axes

**[J]** = Jonathan (dev) · **[T]** = Thomas (graphismes) · **[J+T]** = les deux

---

## 🔵 AXE 1 — Stabilisation & tests en conditions réelles  ← **ON EST ICI**

**Objectif** : que tout ce qui a été construit fonctionne vraiment, testé à deux
comptes, avant d'ajouter quoi que ce soit.

| État | Sujet |
|---|---|
| ☐ | **Guildes** (adhésion, approbation, défis inter-guildes) ← prochain |
| ☐ | Ligue (points, classement de groupe, divisions, promotion/relégation) — était **totalement cassée** (RPC manquantes en base, jamais commitées) puis reconstruite avec le vrai modèle hebdomadaire/divisions le 2026-07-21, à tester à 2 comptes. |
| ☐ | Défis entre amis (profil, Arène/rapide, compétitif/amical) — codé le 2026-07-14, à valider à 2 comptes |
| ☐ | Paliers de monnaie cliquables |
| ☐ | Boucle quotidienne (défi du jour, quêtes, streak, Rush) |
| ☐ | Partage de partie |
| ✅ | **Tournois** — automatisés côté serveur (pg_cron), validés le 2026-07-14 |
| ✅ | Matchmaking (réparé : RLS + fenêtre ELO élargissante) |
| ✅ | Défis entre joueurs (liste en ligne) |
| ✅ | WurmzSkin |

**Règle** : ne pas passer à l'AXE suivant tant que l'AXE 1 n'est pas propre.
Jonathan a explicitement demandé un « hard focus axe 1 ».

---

## 🎨 AXE 2 — Direction artistique & production graphique  **[T]**

**C'est le goulot d'étranglement du projet.** Le jeu est fonctionnellement riche
mais la production graphique ne suit pas.

- Cohérence de la DA (samouraï féodal × cyberpunk)
- Skins de pièces, plateaux, thèmes
- Illustrations des adversaires IA (6 personnages)
- Bandeau de combat (poses illustrées)
- Assets marketing (captures, icônes de store)

---

## 📖 AXE 3 — Scénario & univers  **[J+T]**

Inspirations assumées : **Fate** (invocation de figures historiques) et
**Star Wars** (structure maître/disciple, chute).

- **Musashi** — le maître
- **Shinai** — ancien disciple de Musashi passé du côté sombre. C'est le
  « Vador » du récit.
- Campagne narrative, dialogues, progression

---

## 🔧 AXE 4 — Finitions applicatives  **[J]**

- ~~Brancher les tournois sur de vraies parties~~ ← **en cours, AXE 1**
- **Connexion via Google (OAuth)** — demandée le 2026-07-23. Bloquée côté
  Jonathan : créer un projet Google Cloud Console (écran de consentement OAuth
  + identifiants), URI de redirection à whitelister
  `https://ikssbshpvpqlcgrbjldz.supabase.co/auth/v1/callback`, puis activer
  le provider Google dans Supabase (Authentication → Providers) avec le
  Client ID/Secret obtenus. **Une fois ça fait, prévenir Claude** pour la
  suite côté code : bouton "Se connecter avec Google" + écran post-connexion
  (choix du pseudo + acceptation CGU/confidentialité/âge, puisqu'avec Google
  l'utilisateur arrive déjà authentifié, sans être passé par le formulaire
  d'inscription classique).
- Onboarding / tutoriel
- Notifications push
- Polish UI général
- Performance sur mobile bas de gamme

---

## 📱 AXE 5 — Portage application native (Capacitor)  **[J]**

**Ne pas commencer trop tôt.** Repère donné par Jonathan : on porte quand les
correctifs quotidiens ralentissent, pas avant. Aujourd'hui on itère encore vite
sur le web, ce serait un frein.

À prévoir :
- **Capacitor** (le jeu est déjà un fichier HTML unique, ça devrait bien passer)
- **RevenueCat** — achats intégrés (le Koku est la monnaie premium)
- **Firebase** — notifications push
- **RGPD** — consentement, politique de confidentialité
- **Comptes développeur** : Apple 99 $/an · Google 25 $ une fois

---

## 🏷️ AXE 6 — Marque & jeu physique  **[J+T]**

- Identité de marque
- Édition physique du plateau (le jeu est un abstrait 5×5, ça se prête bien)
- Site vitrine

---

## Décisions structurantes déjà prises

Ces points ont été tranchés, ne pas les remettre en cause sans raison.

1. **Le Koku (石) ne se gagne JAMAIS en jouant.** C'est la monnaie premium.
   Elle n'entre que par la conversion de fin de saison et les achats.
2. **Une monnaie par mode** (Shiso, Tamashii, Mon, Ryu, Hanafuda) + le
   **Shiitake** transverse pour le quotidien.
3. **Saisons de 3 mois** : les monnaies de mode sont converties en Koku puis
   remises à zéro.
4. **Tournois = système suisse**, pas d'élimination. Plafonds par cadence
   (64/32/16) calibrés pour **~20 min** de tournoi. Désertion = abandon,
   le tournoi continue.
5. **Ligue anti-tanking** : on ne gagne que des points, jamais de perte.
6. **Modes coupables sans redéploiement** (drapeaux en base) — vital une fois
   sur les stores, où publier un correctif prend des jours.

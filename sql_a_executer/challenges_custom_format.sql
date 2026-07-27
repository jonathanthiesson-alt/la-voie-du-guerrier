-- ════════════════════════════════════════════════════════════════════════
-- challenges.custom_format — modes personnalisés jouables en ligne (M5 ③)
-- ════════════════════════════════════════════════════════════════════════
-- APPLIQUÉE le 2026-07-28 (via MCP apply_migration « challenges_custom_format »).
--
-- Un défi privé peut désormais porter le DESCRIPTEUR d'un mode construit dans le
-- Labo (dimensions, cases mortes, pièces inventées). À l'acceptation, la partie
-- en ligne est créée sur ce mode : le format voyage ensuite dans
-- online_games.game_state.format (voir createOnlineGame / enterOnlineGame).
--
-- Colonne ADDITIVE nullable : les défis normaux la laissent NULL et sont
-- strictement inchangés. On NE crée PAS de valeur mode='custom' (pour ne pas
-- risquer une contrainte CHECK sur `mode`) : le custom est détecté par la simple
-- présence de custom_format. Aucune policy RLS à modifier — les policies
-- existantes de `challenges` s'appliquent à toutes les colonnes de la ligne.

alter table public.challenges add column if not exists custom_format jsonb;

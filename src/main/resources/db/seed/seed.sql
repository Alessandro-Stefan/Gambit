-- ============================================================
-- Seed di Gambit: dati su larga scala, lenti by design.
--
-- NON e' una migrazione Flyway (passo 7): gira solo in locale, a mano, con psql.
-- Presuppone V1 + V2 applicate e tabelle VUOTE.
--
-- Esecuzione (dal tuo terminale, con il container avviato):
--   docker exec -i <container> psql -U gambit -d gambit -v scale=1 < db/seed/seed.sql
--
-- scale=1    -> volumi pieni (~200k giocatori, ~4M match, ~10M game)
-- scale=0.05 -> prova veloce per controllare che tutto funzioni
--
-- Invarianti GARANTITE (passo 4): chiavi esterne, giocatori dei match iscritti
-- al torneo, al massimo un match per giocatore per round, niente rematch,
-- al massimo un riposo per giocatore per torneo, game coerenti col vincitore.
--
-- Invarianti RILASSATE (documentarle nel README):
--  - gli accoppiamenti seguono il record (vittorie) ma non tutte le regole svizzere
--  - se un accoppiamento casuale e' un rematch o un secondo riposo, il vincolo
--    lo rifiuta e quei giocatori saltano il round
--  - l'Elo "prima" di ogni match e' quello iniziale del giocatore, non quello
--    aggiornato match dopo match: lo storico Elo non si concatena
--  - i tornei piu' grandi possono avere qualche iscritto in meno del previsto
-- ============================================================

\set ON_ERROR_STOP on
\timing on

\if :{?scale}
\else
    \set scale 1
\endif

-- Passo 6: riproducibilita'. Stessa sequenza di random() a ogni esecuzione,
-- a patto che tutto giri in questa sessione.
SELECT setseed(0.42);

-- Piu' memoria per ordinamenti e hash join durante il caricamento
SET work_mem = '256MB';


-- ============================================================
-- 1. Giocatori
--    Elo a campana attorno a 1000 (default di V1): la somma di 6 random()
--    ha media 3 e deviazione standard ~0.71, quindi * 283 -> ~200 punti.
--    Regioni asimmetriche: power(random(), 2) sposta la massa verso le prime.
-- ============================================================
INSERT INTO player (name, avatar_url, region, elo)
SELECT
    'player_' || g,
    'https://cdn.example.com/avatars/' || g || '.png',
    (ARRAY['EU', 'NA', 'JP', 'KR', 'LATAM', 'ME', 'OCE'])[1 + floor(power(random(), 2) * 7)::int],
    greatest(100, round(1000 + (random() + random() + random() + random() + random() + random() - 3) * 283)::int)
FROM generate_series(1, round(200000 * :scale)::int) AS g;


-- ============================================================
-- 2. Tornei, con dimensione per fascia (passo 2)
--    Formato a soglie come nello schema: 3 vittorie per avanzare,
--    3 sconfitte per essere eliminati -> al massimo 5 round.
-- ============================================================
CREATE TEMP TABLE seed_tournament AS
SELECT
    g,
    CASE
        WHEN g <= round(14000 * :scale) THEN 32
        WHEN g <= round(19000 * :scale) THEN 128
        WHEN g <= round(19900 * :scale) THEN 512
        ELSE 4096
    END AS size,
    now() - interval '730 days' + random() * interval '720 days' AS started_at
FROM generate_series(1, round(20000 * :scale)::int) AS g;

INSERT INTO tournament (name, status, wins_to_advance, losses_to_elim, started_at, finished_at)
SELECT 'tournament_' || g, 'FINISHED', 3, 3, started_at, started_at + interval '2 days'
FROM seed_tournament
ORDER BY started_at;   -- id in ordine di tempo, come in produzione

-- Collego la dimensione all'id vero del torneo
CREATE TEMP TABLE seed_size AS
SELECT t.id AS tournament_id, s.size, t.started_at
FROM seed_tournament s
JOIN tournament t ON t.name = 'tournament_' || s.g;


-- ============================================================
-- 3. Iscrizioni (tournament_player)
--    Attivita' asimmetrica: power(random(), 2) sceglie molto piu' spesso
--    i giocatori con indice basso -> pochi giocatori fanno tantissimi tornei.
--    Genero il doppio dei candidati, tolgo i duplicati e tengo i primi N.
-- ============================================================
CREATE TEMP TABLE seed_player AS
SELECT row_number() OVER (ORDER BY id) AS idx, id, elo
FROM player;

CREATE INDEX ON seed_player (idx);
ANALYZE seed_player;

CREATE TEMP TABLE seed_entry AS
WITH candidates AS (
    SELECT
        s.tournament_id,
        s.started_at,
        1 + floor(power(random(), 2) * (SELECT count(*) FROM seed_player))::bigint AS idx
    FROM seed_size s
    CROSS JOIN LATERAL generate_series(1, s.size * 2) AS c
),
distinct_candidates AS (
    SELECT DISTINCT tournament_id, started_at, idx
    FROM candidates
),
numbered AS (
    SELECT
        d.tournament_id,
        d.started_at,
        p.id AS player_id,
        p.elo,
        row_number() OVER (PARTITION BY d.tournament_id ORDER BY random()) AS pick
    FROM distinct_candidates d
    JOIN seed_player p ON p.idx = d.idx
)
SELECT n.tournament_id, n.started_at, n.player_id, n.elo
FROM numbered n
JOIN seed_size s ON s.tournament_id = n.tournament_id
WHERE n.pick <= s.size;

-- Il seed del torneo (la testa di serie) segue l'Elo, come nella realta'
INSERT INTO tournament_player (tournament_id, player_id, seed, status, tournament_started_at)
SELECT
    tournament_id,
    player_id,
    row_number() OVER (PARTITION BY tournament_id ORDER BY elo DESC, player_id),
    'ACTIVE',
    started_at
FROM seed_entry;


-- ============================================================
-- 4. Simulazione dei round
--    Stato dei giocatori in una tabella temporanea: cosi' aggiorno lei
--    (che verra' buttata) e non creo righe morte nelle tabelle vere.
--
--    Ogni round, per TUTTI i tornei insieme (set-based, 5 iterazioni in tutto):
--     - prendo i giocatori ancora in gara (vittorie < 3 e sconfitte < 3)
--     - li ordino per record, poi a caso: accoppio 1 con 2, 3 con 4, ...
--       quindi gli accoppiamenti sono quasi sempre tra pari record
--     - se sono dispari, l'ultimo (record piu' basso) riposa
--     - il vincitore si estrae con la probabilita' attesa dell'Elo
--     - inserisco i match in ordine casuale: i match di tornei diversi
--       finiscono intercalati su disco (passo 5, ordine fisico)
-- ============================================================
CREATE TEMP TABLE seed_state AS
SELECT tournament_id, player_id, elo, 0 AS wins, 0 AS losses
FROM seed_entry;

CREATE INDEX ON seed_state (tournament_id, player_id);
ANALYZE seed_state;

DO $$
DECLARE
    v_round     INT;
    v_max_round INT;
BEGIN
    SELECT max(wins_to_advance + losses_to_elim - 1) INTO v_max_round FROM tournament;

    FOR v_round IN 1..v_max_round LOOP

        WITH alive AS (
            SELECT
                s.tournament_id,
                s.player_id,
                s.elo,
                row_number() OVER (PARTITION BY s.tournament_id
                                   ORDER BY s.wins DESC, s.losses, random()) AS rn,
                count(*) OVER (PARTITION BY s.tournament_id) AS cnt
            FROM seed_state s
            JOIN tournament t ON t.id = s.tournament_id
            WHERE s.wins < t.wins_to_advance
              AND s.losses < t.losses_to_elim
        ),
        pairs AS (
            -- coppie: posizione dispari con la successiva
            SELECT a.tournament_id, a.player_id AS pa, b.player_id AS pb, a.elo AS ea, b.elo AS eb
            FROM alive a
            JOIN alive b ON b.tournament_id = a.tournament_id AND b.rn = a.rn + 1
            WHERE a.rn % 2 = 1
            UNION ALL
            -- riposo: l'ultimo, se i giocatori sono dispari
            SELECT tournament_id, player_id, NULL, elo, NULL
            FROM alive
            WHERE rn = cnt AND cnt % 2 = 1
        ),
        decided AS (
            SELECT
                p.*,
                -- punteggio atteso di A secondo l'Elo (null per il riposo)
                1.0 / (1 + power(10, (p.eb - p.ea) / 400.0)) AS exp_a,
                random() AS roll
            FROM pairs p
        ),
        with_winner AS (
            SELECT
                d.*,
                CASE WHEN d.pb IS NULL OR d.roll < d.exp_a THEN d.pa ELSE d.pb END AS winner,
                -- variazione Elo di A con K = 32 (null per il riposo)
                round(32 * ((CASE WHEN d.roll < d.exp_a THEN 1 ELSE 0 END) - d.exp_a))::int AS delta_a
            FROM decided d
        ),
        inserted AS (
            INSERT INTO match (tournament_id, swiss_round, player_a_id, player_b_id, best_of, winner_id,
                               started_at, finished_at,
                               elo_a_before, elo_b_before, elo_a_delta, elo_b_delta)
            SELECT
                w.tournament_id,
                v_round,
                w.pa,
                w.pb,
                3,
                w.winner,
                s.started_at + (v_round - 1) * interval '1 hour',
                s.started_at + (v_round - 1) * interval '1 hour' + interval '30 minutes',
                CASE WHEN w.pb IS NOT NULL THEN w.ea END,
                w.eb,
                w.delta_a,
                -w.delta_a                -- somma zero: quello che guadagna A lo perde B
            FROM with_winner w
            JOIN seed_size s ON s.tournament_id = w.tournament_id
            ORDER BY random()
            ON CONFLICT DO NOTHING      -- rematch o secondo riposo: scartato
            RETURNING tournament_id, player_a_id, player_b_id, winner_id
        ),
        results AS (
            SELECT tournament_id, player_a_id AS player_id, (winner_id = player_a_id) AS won
            FROM inserted
            UNION ALL
            SELECT tournament_id, player_b_id, (winner_id = player_b_id)
            FROM inserted
            WHERE player_b_id IS NOT NULL
        )
        UPDATE seed_state s
        SET wins   = s.wins   + CASE WHEN r.won THEN 1 ELSE 0 END,
            losses = s.losses + CASE WHEN r.won THEN 0 ELSE 1 END
        FROM results r
        WHERE s.tournament_id = r.tournament_id
          AND s.player_id = r.player_id;

        RAISE NOTICE 'round % completato', v_round;
    END LOOP;
END
$$;


-- ============================================================
-- 5. Game e round di Street Fighter
--    Bo3: il vincitore del match vince 2 game, il perdente 0 o 1.
--    Se il perdente vince un game, e' il game 1 o il 2: il game 3
--    (se c'e') lo vince sempre chi vince il match.
--    Ogni game: chi lo vince ha 2 round, chi lo perde 0 o 1.
-- ============================================================
INSERT INTO game (match_id, game_order, rounds_a, rounds_b)
WITH match_shape AS (
    SELECT
        id,
        (winner_id = player_a_id) AS a_won_match,
        (random() < 0.5)::int     AS loser_games,   -- 0 -> 2-0, 1 -> 2-1
        1 + (random() < 0.5)::int AS loser_game_pos -- quale game vince il perdente
    FROM match
    WHERE player_b_id IS NOT NULL                   -- i riposi non hanno game
),
games AS (
    SELECT
        ms.id AS match_id,
        g.n   AS game_order,
        -- il game e' vinto da A se: A ha vinto il match e questo non e' il game
        -- del perdente, oppure A ha perso il match e questo e' il game del perdente
        (ms.a_won_match = NOT (ms.loser_games = 1 AND g.n = ms.loser_game_pos)) AS a_won_game,
        floor(random() * 2)::int AS loser_rounds
    FROM match_shape ms
    CROSS JOIN LATERAL generate_series(1, 2 + ms.loser_games) AS g(n)
)
SELECT
    match_id,
    game_order,
    CASE WHEN a_won_game THEN 2 ELSE loser_rounds END,
    CASE WHEN a_won_game THEN loser_rounds ELSE 2 END
FROM games;


-- ============================================================
-- 6. Contatori e stato finali
--    Il riposo conta come vittoria e partita giocata (regola di dominio),
--    ma non modifica l'Elo (le sue colonne Elo sono null, sum le ignora).
-- ============================================================
WITH per_player AS (
    SELECT
        player_id,
        count(*)                       AS total,
        count(*) FILTER (WHERE won)    AS wins,
        coalesce(sum(delta), 0)        AS elo_change
    FROM (
        SELECT player_a_id AS player_id, (winner_id = player_a_id) AS won, elo_a_delta AS delta
        FROM match
        UNION ALL
        SELECT player_b_id, (winner_id = player_b_id), elo_b_delta
        FROM match
        WHERE player_b_id IS NOT NULL
    ) x
    GROUP BY player_id
)
UPDATE player p
SET wins          = pp.wins,
    total_matches = pp.total,
    elo           = greatest(0, p.elo + pp.elo_change)
FROM per_player pp
WHERE pp.player_id = p.id;

UPDATE tournament_player tp
SET status = CASE
                 WHEN s.wins   >= t.wins_to_advance THEN 'ADVANCED'
                 WHEN s.losses >= t.losses_to_elim  THEN 'ELIMINATED'
                 ELSE 'ACTIVE'   -- ha saltato round per rematch scartati: rilassato
             END
FROM seed_state s
JOIN tournament t ON t.id = s.tournament_id
WHERE tp.tournament_id = s.tournament_id
  AND tp.player_id = s.player_id;


-- ============================================================
-- 7. Dopo il caricamento (passo 8)
--    Gli UPDATE sopra hanno lasciato una versione morta per ogni riga di
--    player e tournament_player (MVCC!). VACUUM normale le rende riutilizzabili
--    ma non restringe il file: le tabelle resterebbero grandi il doppio e
--    le misure sarebbero falsate. VACUUM FULL le riscrive compatte.
--    Poi VACUUM ANALYZE su tutto: statistiche per il planner e visibility
--    map pronta per gli index-only scan.
-- ============================================================
VACUUM FULL player;
VACUUM FULL tournament_player;
VACUUM ANALYZE;


-- ============================================================
-- 8. Riepilogo: confronta con le predizioni del passo 2
-- ============================================================
SELECT 'player'            AS tabella, count(*) AS righe, pg_size_pretty(pg_total_relation_size('player'))            AS dimensione_totale FROM player
UNION ALL
SELECT 'tournament',        count(*), pg_size_pretty(pg_total_relation_size('tournament'))        FROM tournament
UNION ALL
SELECT 'tournament_player', count(*), pg_size_pretty(pg_total_relation_size('tournament_player')) FROM tournament_player
UNION ALL
SELECT 'match',             count(*), pg_size_pretty(pg_total_relation_size('match'))             FROM match
UNION ALL
SELECT 'game',              count(*), pg_size_pretty(pg_total_relation_size('game'))              FROM game;
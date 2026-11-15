CREATE TABLE player (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    avatar_url  VARCHAR(255),
    region      VARCHAR(50)  NOT NULL,
    elo         INTEGER      NOT NULL DEFAULT 1000 CHECK (elo >= 0)
);

CREATE UNIQUE INDEX uq_player_name_ci ON player (LOWER(name));

CREATE TABLE tournament (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(100) NOT NULL UNIQUE,
    status          VARCHAR(20)  NOT NULL
                    CHECK (status IN ('REGISTRATION', 'IN_PROGRESS', 'FINISHED')),
    wins_to_advance SMALLINT     NOT NULL CHECK (wins_to_advance > 0),
    losses_to_elim  SMALLINT     NOT NULL CHECK (losses_to_elim > 0),
    started_at      TIMESTAMPTZ,
    finished_at     TIMESTAMPTZ,
                    CHECK (finished_at IS NULL OR (started_at IS NOT NULL AND finished_at >= started_at))
);

CREATE TABLE tournament_player (
    tournament_id   BIGINT      NOT NULL REFERENCES tournament (id),
    player_id       BIGINT      NOT NULL REFERENCES player (id),
    seed            SMALLINT    NOT NULL CHECK (seed > 0),
    status          VARCHAR(20) NOT NULL
                    CHECK (status IN ('ACTIVE', 'ADVANCED', 'ELIMINATED')),

    PRIMARY KEY (tournament_id, player_id),
    UNIQUE (tournament_id, seed)
);

CREATE INDEX ix_tournament_player_player ON tournament_player (player_id);

CREATE TABLE match (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tournament_id   BIGINT   NOT NULL REFERENCES tournament (id),
    swiss_round     SMALLINT NOT NULL CHECK (swiss_round > 0),
    player_a_id     BIGINT   NOT NULL,
    player_b_id     BIGINT,
    best_of         SMALLINT NOT NULL CHECK (best_of IN (3, 5)),
    winner_id       BIGINT,
    started_at      TIMESTAMPTZ,
    finished_at     TIMESTAMPTZ,

    FOREIGN KEY (tournament_id, player_a_id) REFERENCES tournament_player (tournament_id, player_id),
    FOREIGN KEY (tournament_id, player_b_id) REFERENCES tournament_player (tournament_id, player_id),

    CHECK (player_b_id IS NULL OR player_a_id <> player_b_id),
    CHECK (winner_id IS NULL OR winner_id = player_a_id OR winner_id = player_b_id),
    CHECK (player_b_id IS NOT NULL OR winner_id = player_a_id),
    CHECK (finished_at IS NULL OR (started_at IS NOT NULL AND finished_at >= started_at))
);

-- Niente rematch nello stesso torneo, indipendentemente dall'ordine A/B
CREATE UNIQUE INDEX uq_match_no_rematch
    ON match (tournament_id, LEAST(player_a_id, player_b_id), GREATEST(player_a_id, player_b_id))
    WHERE player_b_id IS NOT NULL;

-- Al massimo un riposo per giocatore per torneo
CREATE UNIQUE INDEX uq_match_one_bye
    ON match (tournament_id, player_a_id)
    WHERE player_b_id IS NULL;

-- FK composite e le query "match di un giocatore nel torneo"
CREATE INDEX ix_match_tournament_player_a ON match (tournament_id, player_a_id);
CREATE INDEX ix_match_tournament_player_b ON match (tournament_id, player_b_id)
    WHERE player_b_id IS NOT NULL;

-- Generazione degli accoppiamenti del round successivo
CREATE INDEX ix_match_tournament_round ON match (tournament_id, swiss_round);

CREATE TABLE game (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    match_id    BIGINT   NOT NULL REFERENCES match (id) ON DELETE CASCADE,
    game_order  SMALLINT NOT NULL CHECK (game_order BETWEEN 1 AND 5),
    rounds_a    SMALLINT NOT NULL CHECK (rounds_a >= 0),
    rounds_b    SMALLINT NOT NULL CHECK (rounds_b >= 0),
    CHECK (rounds_a <> rounds_b),
    UNIQUE (match_id, game_order)
);
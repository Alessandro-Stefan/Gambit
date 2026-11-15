--  Classifica di torneo: la "fotografia" per round
--  Regola di dominio: ordine degli spareggi: punti, Buchholz, differenza game, differenza round, player_id.
--  Solo INSERT, mai UPDATE: nessuna riga morta, storico round per round.
CREATE TABLE standing_snapshot (
    tournament_id BIGINT   NOT NULL,
    swiss_round   SMALLINT NOT NULL CHECK (swiss_round > 0),
    player_id     BIGINT   NOT NULL,
    position      INTEGER  NOT NULL CHECK (position > 0),
    points        SMALLINT NOT NULL CHECK (points >= 0),
    buchholz      INTEGER  NOT NULL CHECK (buchholz >= 0),
    game_diff     INTEGER  NOT NULL,
    round_diff    INTEGER  NOT NULL,
    -- Un giocatore compare una sola volta per round
    PRIMARY KEY (tournament_id, swiss_round, player_id),
    -- Due giocatori non possono avere la stessa posizione, e questo indice
    UNIQUE (tournament_id, swiss_round, position),
    FOREIGN KEY (tournament_id, player_id)
        REFERENCES tournament_player (tournament_id, player_id)
);

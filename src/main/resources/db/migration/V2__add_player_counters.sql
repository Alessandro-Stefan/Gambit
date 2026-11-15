--  Profilo giocatore: contatori denormalizzati
--  Regola di dominio: il riposo conta come vittoria e come partita giocata.
ALTER TABLE player
    ADD COLUMN wins          INTEGER NOT NULL DEFAULT 0 CHECK (wins >= 0),
    ADD COLUMN total_matches INTEGER NOT NULL DEFAULT 0 CHECK (total_matches >= 0);
 
ALTER TABLE player
    ADD CONSTRAINT ck_player_wins_le_total CHECK (wins <= total_matches);
 
ALTER TABLE tournament_player
    ADD COLUMN tournament_started_at TIMESTAMPTZ;    

CREATE INDEX ix_tournament_player_history
    ON tournament_player (player_id, tournament_started_at DESC, tournament_id DESC);
 
DROP INDEX ix_tournament_player_player;

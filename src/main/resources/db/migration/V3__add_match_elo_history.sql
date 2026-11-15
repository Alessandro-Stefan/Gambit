--  Storico Elo sul match
--  Regola di dominio: il riposo NON modifica l'Elo (niente inflazione)
ALTER TABLE match
    ADD COLUMN elo_a_before INTEGER,
    ADD COLUMN elo_b_before INTEGER,
    ADD COLUMN elo_a_delta  INTEGER,
    ADD COLUMN elo_b_delta  INTEGER;
 
ALTER TABLE match
    ADD CONSTRAINT ck_match_bye_no_elo CHECK (
        player_b_id IS NOT NULL
        OR (elo_a_before IS NULL AND elo_b_before IS NULL
            AND elo_a_delta IS NULL AND elo_b_delta IS NULL)
    );

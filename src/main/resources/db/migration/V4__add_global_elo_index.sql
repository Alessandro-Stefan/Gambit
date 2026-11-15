--  Classifica globale per Elo
CREATE INDEX ix_player_leaderboard
    ON player (elo DESC, id DESC)
    WHERE total_matches > 0;

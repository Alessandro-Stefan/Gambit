package it.bingus.gambit.entity;

import java.io.Serializable;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;

@Embeddable
public record TournamentPlayerId(
        @Column(name = "tournament_id") Long tournamentId,
        @Column(name = "player_id") Long playerId) implements Serializable {
}

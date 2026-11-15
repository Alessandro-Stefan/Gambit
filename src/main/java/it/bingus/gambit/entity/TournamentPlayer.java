package it.bingus.gambit.entity;

import java.util.Objects;

import org.springframework.data.domain.Persistable;

import it.bingus.gambit.enums.ParticipantStatus;
import jakarta.persistence.Column;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.MapsId;
import jakarta.persistence.PostLoad;
import jakarta.persistence.PostPersist;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;
import jakarta.validation.constraints.Min;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.ToString;

@Entity
@Table(name = "tournament_player")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@ToString(onlyExplicitlyIncluded = true)
public class TournamentPlayer implements Persistable<TournamentPlayerId> {

    @ToString.Include
    @EmbeddedId
    private TournamentPlayerId id;

    @MapsId("tournamentId")
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "tournament_id")
    private Tournament tournament;

    @MapsId("playerId")
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "player_id")
    private Player player;

    @Min(1)
    @ToString.Include
    @Column(nullable = false)
    private short seed;

    @ToString.Include
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private ParticipantStatus status;

    @Transient
    @Getter(AccessLevel.NONE)
    private boolean isNew = true;

    public TournamentPlayer(Tournament tournament, Player player, short seed) {
        this.id = new TournamentPlayerId(tournament.getId(), player.getId());
        this.tournament = tournament;
        this.player = player;
        this.seed = seed;
        this.status = ParticipantStatus.ACTIVE;
    }

    public void advance() {
        requireStatus(ParticipantStatus.ACTIVE);
        this.status = ParticipantStatus.ADVANCED;
    }

    public void eliminate() {
        requireStatus(ParticipantStatus.ACTIVE);
        this.status = ParticipantStatus.ELIMINATED;
    }

    private void requireStatus(ParticipantStatus expected) {
        if (status != expected) {
            throw new IllegalStateException(
                    "Transizione illegale da " + status + " per " + id);
        }
    }

    @Override
    public boolean isNew() {
        return isNew;
    }

    @PostPersist
    @PostLoad
    void markNotNew() {
        this.isNew = false;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o)
            return true;
        if (!(o instanceof TournamentPlayer other))
            return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return Objects.hashCode(id);
    }
}

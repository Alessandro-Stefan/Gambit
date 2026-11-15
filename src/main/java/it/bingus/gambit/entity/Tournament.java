package it.bingus.gambit.entity;

import java.time.Instant;

import it.bingus.gambit.enums.TournamentStatus;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.validation.constraints.Min;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.ToString;

@Entity
@Table(name = "tournament")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@ToString(onlyExplicitlyIncluded = true)
public class Tournament {

    @ToString.Include
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ToString.Include
    @Column(nullable = false, unique = true, length = 100)
    private String name;

    @ToString.Include
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private TournamentStatus status;

    @Min(1)
    @Column(name = "wins_to_advance", nullable = false)
    private short winsToAdvance;

    @Min(1)
    @Column(name = "losses_to_elim", nullable = false)
    private short lossesToElim;

    @Column(name = "started_at", nullable = false, updatable = false)
    private Instant startedAt;

    @Column(name = "finished_at")
    private Instant finishedAt;

    public Tournament(String name, short winsToAdvance, short lossesToElim, Instant now) {
        if (name.isBlank()) {
            throw new IllegalArgumentException("Invalid name");
        }
        this.name = name;
        this.winsToAdvance = winsToAdvance;
        this.lossesToElim = lossesToElim;
        this.status = TournamentStatus.REGISTRATION;
        this.startedAt = now;
    }

    public void finish(Instant now) {
        if (status != TournamentStatus.IN_PROGRESS) {
            throw new IllegalStateException("Tournament not in progress: " + status);
        }
        this.status = TournamentStatus.FINISHED;
        this.finishedAt = now;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o)
            return true;
        if (!(o instanceof Tournament other))
            return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return Tournament.class.hashCode();
    }
}

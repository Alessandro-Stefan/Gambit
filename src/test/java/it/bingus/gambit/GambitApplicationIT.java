package it.bingus.gambit;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.postgresql.PostgreSQLContainer;

@SpringBootTest
@Testcontainers
public class GambitApplicationIT {
    @Container
    @ServiceConnection
    static PostgreSQLContainer pg = new PostgreSQLContainer("postgres:18");

    @Test
    void contextLoads_andFlywayMigrates() {
    } // se parte, V1/V2 si applicano e validate passa
}

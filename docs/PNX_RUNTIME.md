# PowerNukkitX runtime recovery

The network keeps PvP, BedWars and SkyWars on PowerNukkitX while Lobby and Survival remain on official BDS.

## Runtime source policy

The updater first tries the upstream URL currently documented by PowerNukkitX:

`https://github.com/PowerNukkitX/PowerNukkitX/releases/download/snapshot/powernukkitx-shaded.jar`

Upstream may temporarily remove or rename that snapshot asset. A missing asset must not make a fresh Nexora installation unrecoverable.

When the published shaded JAR is unavailable, `scripts/update-pnx.sh` builds the runnable shaded JAR from the pinned upstream source configured in `config/engines.env`.

The fallback is deliberately reproducible:

- repository must be the official `PowerNukkitX/PowerNukkitX` repository;
- source is pinned to a full 40-character commit SHA;
- the pinned README must advertise the expected PowerNukkitX and Bedrock versions;
- Java 21+ is required;
- upstream's own Gradle wrapper runs the `shadowJar` task;
- the resulting JAR must contain `org/powernukkitx/JarStart.class` before it can be activated;
- the upstream commit and source kind are recorded with the installed release.

Do not replace the shaded runtime with a thin Maven library JAR: the server needs its runtime dependencies packaged for standalone execution.

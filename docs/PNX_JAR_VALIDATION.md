# Validación del runtime PowerNukkitX

MinecraftServer valida el JAR ejecutable de PowerNukkitX sin usar tuberías `jar tf | grep -q`, porque bajo `set -o pipefail` una salida grande puede provocar `SIGPIPE` en `jar` y producir un falso negativo.

La validación actual usa Python `zipfile` y exige:

- archivo JAR/ZIP íntegro;
- `org/powernukkitx/JarStart.class` presente;
- `META-INF/MANIFEST.MF` presente;
- `Main-Class: org.powernukkitx.JarStart`.

Una release construida desde el mismo commit fijado se reutiliza en bootstraps posteriores si sigue pasando esta validación, evitando recompilar Gradle innecesariamente mientras el snapshot upstream no esté disponible.

# Preparación del lobby

El lobby se construye como una **isla flotante tipo hub** a Y=160. La base no necesita descargarse como mapa externo: el propio Behavior Pack puede generarla de forma reproducible.

## Primera construcción

1. La instalación automática inicia el lobby una vez para crear el mundo `Lobby` e instala `addons/lobby_bp`.
2. Desde la consola de BDS concede al constructor la etiqueta administrativa:

```text
tag "TuGamertag" add network.admin
```

3. Entra al lobby y escribe:

```text
!buildhub
```

4. El generador crea la isla central, plaza, caminos y cuatro plataformas:

```text
                 NORTE
               SURVIVAL
                  │
                  │
 OESTE SKYWARS ─ SPAWN ─ PVP ESTE
                  │
                  │
               BEDWARS
                  SUR
```

5. Crea cuatro NPC con estos nombres exactos:

- `Survival`
- `PvP`
- `BedWars`
- `SkyWars`

6. Los jugadores pueden interactuar con los NPC o usar una brújula/`!menu`.
7. Cuando termines de construir, puedes retirar la etiqueta:

```text
tag "TuGamertag" remove network.admin
```

## Seguridad

El lobby tiene cheats habilitados deliberadamente porque `/transfer` y las herramientas administrativas del hub los requieren. **Esto no habilita cheats en Survival**: Survival vive en otra instancia BDS, utiliza otro mundo y mantiene `allow-cheats=false`.

La isla generada es la estructura base. Puede decorarse después con construcciones, vegetación, cascadas, hologramas, portales y zonas temáticas sin cambiar la arquitectura de la red.

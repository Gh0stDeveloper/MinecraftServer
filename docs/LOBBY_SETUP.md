# Preparación del lobby

El lobby se construye como una **isla flotante tipo hub** a Y=160.

1. Inicia `bedrock@lobby` una vez para que BDS cree el mundo `Lobby`.
2. Detén el servidor.
3. Instala `addons/lobby_bp` con `scripts/install-addon.sh`.
4. Reinicia el lobby.
5. Concede temporalmente al constructor la etiqueta `network.admin` desde consola:

```text
tag "TuGamertag" add network.admin
```

6. Dentro del juego ejecuta `!buildhub` para generar la isla base.
7. Crea cuatro NPC llamados exactamente: `Survival`, `PvP`, `BedWars`, `SkyWars`, siguiendo `docs/LOBBY_ISLAND.md`.
8. Los jugadores también pueden usar una brújula o `!menu`.
9. Retira la etiqueta de administrador cuando termines si no la necesitas.

El lobby tiene cheats habilitados deliberadamente porque `/transfer` y la generación administrativa del hub los requieren. Esto no afecta al Survival porque es otro mundo y otra instancia BDS completamente separada.

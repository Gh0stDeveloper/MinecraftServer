# Minijuegos

La red separa la lógica de juego del Survival. Todo lo descrito aquí ocurre en las instancias PNX de PvP, BedWars y SkyWars.

## PvP — NexoraPractice 0.2

PvP no requiere mapas externos. NexoraPractice genera una zona de espera y varias arenas en altura segura cuando la instancia inicia.

Modalidades:

| Comando | Equipos | Jugadores requeridos |
|---|---:|---:|
| `/pvp solo` | 1 vs 1 | 2 |
| `/pvp duo` | 2 vs 2 | 4 |
| `/pvp squad` | 4 vs 4 | 8 |

Flujo de partida:

1. el jugador entra en una cola;
2. cuando existe el número requerido de jugadores, se reserva una arena libre;
3. los jugadores se dividen en dos equipos;
4. reciben el kit PvP;
5. comienza una ronda;
6. morir o caer al vacío elimina al jugador de esa ronda y lo mueve a espectador;
7. el último equipo vivo gana la ronda;
8. la partida termina al alcanzar `first-to` victorias, por defecto 3;
9. la arena se libera y los jugadores vuelven a la zona de espera.

Comandos:

```text
/pvp solo
/pvp duo
/pvp squad
/pvp leave
/pvp status
/lobby
```

Un operador también puede reconstruir la infraestructura cuando no haya partidas activas:

```text
/pvp rebuild
```

Configuración del plugin:

```yaml
lobby-host: 147.224.196.17
lobby-port: 19132
arena-base-y: 180
arena-slots: 8
first-to: 3
```

`plugin-manager.sh` conserva esos ajustes al actualizar el plugin y solo actualiza automáticamente el host/puerto del lobby.

## BedWars

SilentBedwars se mantiene como plugin upstream fijado, pero su implementación actual espera explícitamente un nivel llamado `world`. Por eso la instancia BedWars utiliza:

```ini
level-name=world
```

Un mundo vacío generado automáticamente **no** habilita BedWars. El lobby exige además el marcador `minigames/bedwars-map.ready`, que solo crea el importador administrado.

Importar un mapa Bedrock existente:

```bash
sudo mcserver minigames import-bedwars "/ruta/al/MapaBedWars"
```

El directorio debe contener como mínimo:

```text
MapaBedWars/
├── level.dat
└── db/
```

El importador:

- detiene BedWars si estaba activo;
- hace backup del mapa anterior;
- instala el mundo como `instances/bedwars/worlds/world`;
- crea el marcador de mapa validado;
- conserva el estado previo del servicio;
- actualiza la disponibilidad mostrada en el lobby.

### Limitación del upstream actual

La versión fijada de SilentBedwars todavía contiene coordenadas predeterminadas para dos bases y sus generadores. Por eso el primer mapa debe corresponder a esa arena o, en un bloque posterior, sustituiremos esa parte por nuestro motor BedWars propio/configurable. El lobby mantiene BedWars bloqueado hasta que el administrador realice la importación de forma explícita.

## SkyWars

PowerSkywars soporta mapas externos en:

```text
plugins/PowerSkywars/maps/<nombre>/
```

y una configuración `maps_config.yml` con `spawns` y `mid`.

El proyecto administra ambos elementos para evitar editar YAML manualmente.

Ejemplo:

```bash
sudo mcserver minigames import-skywars Islas1 "/ruta/Islas1" \
  --spawns "20,70,0;-20,70,0;0,70,20;0,70,-20" \
  --mid "0,68,0"
```

Las coordenadas deben ser enteros `x,y,z`. Se requieren al menos dos spawns.

El importador:

- valida `level.dat` y `db/`;
- hace backup si el mapa ya existía;
- copia el mapa al directorio del plugin;
- registra spawns y centro en `minigames/skywars-maps.json`;
- regenera `maps_config.yml`;
- conserva el estado del servicio;
- actualiza el menú del lobby.

Eliminar un mapa:

```bash
sudo mcserver minigames remove-skywars Islas1
```

## Estado y validación

```bash
sudo mcserver minigames status
sudo mcserver minigames verify
```

`status` diferencia `LISTO` y `NO LISTO`. `verify` detecta inconsistencias entre marcadores, plugins, manifiestos y carpetas de mapas.

## Lobby

El lobby recibe un objeto `NETWORK.ready` generado desde el estado real de la VPS:

- Survival: disponible por diseño;
- PvP: disponible cuando NexoraPractice está instalado;
- BedWars: disponible solo con plugin + mundo + marcador de importación;
- SkyWars: disponible solo con plugin + al menos un mapa importado.

Si una modalidad no está preparada, el menú y los NPC no transfieren al jugador y muestran `PREPARANDO MAPA`.

Esto evita enviar usuarios a una instancia técnicamente encendida pero todavía sin contenido jugable.

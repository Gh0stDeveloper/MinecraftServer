# Minijuegos

PvP, BedWars y SkyWars se ejecutan en instancias PowerNukkitX separadas. Survival no recibe ninguno de estos plugins.

## PvP — NexoraPractice 0.2

PvP genera una zona de espera y hasta 8 arenas automáticamente.

| Comando | Equipos | Jugadores |
|---|---:|---:|
| `/pvp solo` | 1 vs 1 | 2 |
| `/pvp duo` | 2 vs 2 | 4 |
| `/pvp squad` | 4 vs 4 | 8 |

La partida es `first-to-3`, incluye kit PvP, friendly-fire bloqueado, muerte/vacío, espectador y reutilización de arena.

```text
/pvp solo
/pvp duo
/pvp squad
/pvp leave
/pvp status
/lobby
```

## BedWars — NexoraBedWars 0.1

NexoraBedWars es ahora el motor predeterminado y **no requiere mapas externos**. El plugin construye las arenas al iniciar.

| Comando | Equipos | Jugadores |
|---|---:|---:|
| `/bw solo` | 1 vs 1 | 2 |
| `/bw duo` | 2 vs 2 | 4 |
| `/bw squad` | 4 vs 4 | 8 |

Cada arena contiene:

- base Roja;
- base Azul;
- isla central;
- vacío entre islas para construir puentes;
- una cama-núcleo Roja y una Azul;
- estructura protegida contra roturas accidentales.

### Reglas

1. mientras la cama-núcleo del equipo siga viva, un jugador muerto reaparece;
2. al destruir la cama rival, ese equipo pierde la capacidad de reaparecer;
3. la siguiente muerte de cada jugador de ese equipo es definitiva;
4. cuando un equipo queda sin jugadores vivos, el rival gana;
5. todos los bloques colocados durante la partida se eliminan al terminar y la arena vuelve a su estado inicial.

### Recursos y tienda

Los jugadores reciben hierro periódicamente y oro cada varios ciclos. La configuración por defecto es:

```yaml
iron-period-ticks: 40
gold-period-cycles: 5
```

Tienda:

```text
/bw shop blocks   # 4 hierro -> 16 bloques del color del equipo
/bw shop sword    # 10 hierro -> espada de piedra
/bw shop pickaxe  # 12 hierro -> pico de hierro
/bw shop bow      # 8 oro -> arco + flechas
```

Solo se pueden romper bloques colocados durante la partida o la cama-núcleo rival. Friendly-fire está bloqueado.

Comandos completos:

```text
/bw solo
/bw duo
/bw squad
/bw leave
/bw status
/bw shop <blocks|sword|pickaxe|bow>
/lobby
```

Un operador puede reconstruir las arenas cuando no existen partidas activas:

```text
/bw rebuild
```

Configuración:

```yaml
lobby-host: 147.224.196.17
lobby-port: 19132
arena-base-y: 180
arena-slots: 4
iron-period-ticks: 40
gold-period-cycles: 5
```

### SilentBedwars como fallback

SilentBedwars continúa en el catálogo, pero con `auto_install=false`. No se ejecuta junto a NexoraBedWars.

Para cambiar manualmente al fallback:

```bash
sudo mcserver plugins install silentbedwars
```

El administrador elimina `nexora-bedwars.jar` antes de activar el fallback. SilentBedwars sí necesita un mundo `world`, por lo que para ese modo legacy se mantiene:

```bash
sudo mcserver minigames import-bedwars "/ruta/al/MapaBedWars"
```

Para volver al motor propio:

```bash
sudo mcserver plugins install nexora-bedwars
sudo mcserver minigames prepare
```

## SkyWars — PowerSkywars

SkyWars continúa usando PowerSkywars con mapas administrados. Se importa cada mapa junto con sus spawns y centro:

```bash
sudo mcserver minigames import-skywars Islas1 "/ruta/Islas1" \
  --spawns "20,70,0;-20,70,0;0,70,20;0,70,-20" \
  --mid "0,68,0"
```

El sistema valida `level.dat`/`db`, crea backup, copia el mapa, actualiza `minigames/skywars-maps.json` y regenera `maps_config.yml`.

Eliminar:

```bash
sudo mcserver minigames remove-skywars Islas1
```

## Estado

```bash
sudo mcserver minigames status
sudo mcserver minigames verify
sudo mcserver plugins doctor
```

El lobby usa `NETWORK.ready`:

- Survival: disponible por diseño;
- PvP: listo con NexoraPractice;
- BedWars: listo con NexoraBedWars sin importar mapa, o con el fallback legacy completamente configurado;
- SkyWars: listo cuando existe PowerSkywars y al menos un mapa válido.

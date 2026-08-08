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

NexoraBedWars es el motor predeterminado y **no requiere mapas externos**.

| Comando | Equipos | Jugadores |
|---|---:|---:|
| `/bw solo` | 1 vs 1 | 2 |
| `/bw duo` | 2 vs 2 | 4 |
| `/bw squad` | 4 vs 4 | 8 |

Cada arena contiene dos bases, centro, vacío para puentes y una cama-núcleo por equipo. Mientras la cama siga viva hay respawn; destruida la cama, la siguiente muerte es definitiva. La estructura base está protegida y al terminar se eliminan los bloques temporales.

Tienda:

```text
/bw shop blocks   # 4 hierro -> 16 bloques del equipo
/bw shop sword    # 10 hierro -> espada de piedra
/bw shop pickaxe  # 12 hierro -> pico de hierro
/bw shop bow      # 8 oro -> arco + flechas
```

Comandos:

```text
/bw solo
/bw duo
/bw squad
/bw leave
/bw status
/bw shop <blocks|sword|pickaxe|bow>
/bw rebuild       # operador, sin partidas activas
/lobby
```

### SilentBedwars como fallback

```bash
sudo mcserver plugins install silentbedwars
sudo mcserver minigames import-bedwars "/ruta/al/MapaBedWars"
```

Para volver al motor nativo:

```bash
sudo mcserver plugins install nexora-bedwars
sudo mcserver minigames prepare
```

Los dos JAR son incompatibles entre sí; `plugin-manager` elimina automáticamente el motor conflictivo.

## SkyWars — NexoraSkyWars 0.1

NexoraSkyWars es el motor predeterminado y **tampoco necesita mapas externos**. Genera hasta 2 arenas por defecto, cada una con cuatro islas y una isla central.

| Comando | Equipos | Jugadores |
|---|---:|---:|
| `/sw solo` | 4 equipos de 1 | 4 |
| `/sw duo` | 4 equipos de 2 | 8 |
| `/sw squad` | 4 equipos de 4 | 16 |

Equipos:

- Rojo;
- Azul;
- Verde;
- Amarillo.

### Flujo

1. cada equipo aparece en una isla independiente;
2. recibe espada de madera y 16 bloques del color del equipo;
3. cada isla posee un loot-crate inicial;
4. el centro contiene loot-crates de mejor nivel;
5. los jugadores construyen puentes hacia otras islas o el centro;
6. no existe respawn;
7. morir o caer al vacío elimina al jugador y lo convierte en espectador;
8. el último equipo con jugadores vivos gana;
9. los puentes, bloques temporales y crates se limpian/restauran automáticamente.

Loot de isla puede entregar espada de piedra, pico de hierro, arco/flechas o manzana dorada. El loot central puede entregar espada de hierro, más flechas, ender pearls o manzanas doradas.

La estructura del mapa está protegida: solo se pueden romper bloques colocados durante la partida o loot-crates.

Comandos:

```text
/sw solo
/sw duo
/sw squad
/sw leave
/sw status
/sw rebuild       # operador, sin partidas activas
/lobby
```

Configuración:

```yaml
lobby-host: 147.224.196.17
lobby-port: 19132
arena-base-y: 180
arena-slots: 2
```

### PowerSkywars como fallback

PowerSkywars permanece disponible con `auto_install=false`:

```bash
sudo mcserver plugins install powerskywars
```

Al activar el fallback se retira `nexora-skywars.jar`. PowerSkywars sí utiliza mapas externos; solo para ese modo legacy se conservan:

```bash
sudo mcserver minigames import-skywars Islas1 "/ruta/Islas1" \
  --spawns "20,70,0;-20,70,0;0,70,20;0,70,-20" \
  --mid "0,68,0"
```

Para volver al motor nativo:

```bash
sudo mcserver plugins install nexora-skywars
sudo mcserver minigames prepare
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
- BedWars: listo con NexoraBedWars, o con el fallback legacy completamente configurado;
- SkyWars: listo con NexoraSkyWars, o con PowerSkywars + mapa legacy válido.

# BedrockNetwork

Red de servidores para Minecraft Bedrock 1.26.40 basada en Bedrock Dedicated Server (BDS) oficial.

## Objetivos de esta primera base

- Lobby independiente en una **isla flotante generable**, con NPC/menú para enviar jugadores a otros servidores.
- Survival independiente y conservador para proteger los logros del mundo existente.
- Instancias separadas para PvP, BedWars y SkyWars.
- Menús Solo / Duo / Escuadra en los minijuegos.
- Servicios systemd y reinicio automático ante fallo.
- Importación segura del mundo Survival con backup previo.
- Backups rotativos del Survival.
- Allowlist y autenticación Xbox Live en Survival.
- Estructura preparada para colas, arenas, estadísticas y panel web.

## Regla crítica: logros del Survival

El Survival no comparte el Behavior Pack del lobby ni el de los minijuegos.

Configuración obligatoria:

```ini
allow-cheats=false
force-gamemode=false
gamemode=survival
online-mode=true
allow-list=true
```

No actives cheats, Creative, experimentos ni packs que puedan marcar el mundo como no apto para logros. El script de importación **no modifica `level.dat`**: copia el mundo tal cual y genera una copia de seguridad antes de reemplazar cualquier mundo existente.

> Si el mundo ya tuvo cheats/Creative/experimentos activados alguna vez, moverlo a BDS no puede restaurar los logros. La protección de este proyecto evita introducir esos cambios desde el servidor.

## Arquitectura

```text
Jugador Bedrock
     |
     | UDP 19132
     v
+-----------+
|   LOBBY   |  cheats=true, scripts permitidos
+-----+-----+
      |
      +--> Survival  UDP 19133  cheats=false, sin scripts propios
      +--> PvP       UDP 19134  cheats=true
      +--> BedWars   UDP 19135  cheats=true
      +--> SkyWars   UDP 19136  cheats=true
```

La transferencia desde el lobby usa `/transfer`. Como ese comando requiere cheats, se ejecuta únicamente en lobby/minijuegos. El Survival permanece con cheats desactivados. En esta fase, para volver desde Survival al lobby se sale del servidor Survival y se vuelve a entrar a la dirección principal del lobby.

## Requisitos VPS

- Ubuntu 22.04/24.04 x86_64.
- CPU AMD64/x86_64 (AMD o Intel).
- 8 GB RAM mínimo; 12 GB recomendado para esta red.
- BDS oficial de la misma versión que los clientes.
- Puertos UDP 19132-19136 abiertos.

## Instalación desde GitHub

En la VPS podrás obtener el proyecto directamente con:

```bash
git clone https://github.com/Gh0stDeveloper/MinecraftServer.git
cd MinecraftServer
```

GitHub Actions también genera un artefacto `bedrock-network.tar.gz` después de validar cada cambio en `main`.

## Instalación resumida

1. Descarga el ZIP oficial de Bedrock Dedicated Server para Linux desde Minecraft.
2. Sube este proyecto y el ZIP a la VPS.
3. Ejecuta:

```bash
sudo ./scripts/bootstrap.sh
sudo ./scripts/install-network.sh /ruta/al/bedrock-server-linux.zip
```

4. Edita `config/network.env` y cambia `PUBLIC_HOST` por la IP o dominio del servidor.
5. Aplica la configuración del lobby:

```bash
sudo ./scripts/render-lobby-config.sh
```

6. Inicia primero el lobby para que genere su mundo:

```bash
sudo systemctl start bedrock@lobby
```

7. Instala el addon del lobby:

```bash
sudo ./scripts/install-addon.sh lobby addons/lobby_bp
sudo systemctl restart bedrock@lobby
```

8. Construye la isla flotante siguiendo `docs/LOBBY_ISLAND.md`. El comando administrativo es `!buildhub`.

9. Importa tu mundo Survival (con el servidor Survival detenido):

```bash
sudo ./scripts/import-survival.sh "/ruta/a/TuMundo"
```

10. Inicia la red:

```bash
sudo ./scripts/start-network.sh
```

## Estado de los minijuegos

Esta primera entrega crea el framework de los minijuegos y las colas. Las arenas físicas todavía deben construirse/importarse y luego registrar sus coordenadas en cada `config.js`.

- PvP: estados de cola para Solo (1v1), Duo (2v2) y Escuadra (4v4).
- BedWars: cola Solo/Duo/Escuadra y registro de arenas preparado.
- SkyWars: cola Solo/Duo/Escuadra y registro de arenas preparado.

La siguiente fase puede implementar arenas clonables, generadores, tiendas, camas, loot, espectador, temporizadores, reset automático y estadísticas persistentes.

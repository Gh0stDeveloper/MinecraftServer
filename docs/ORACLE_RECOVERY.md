# Recuperación de instalación incompleta en Oracle Cloud

Este flujo está pensado para una VPS donde el proyecto y systemd ya existen, pero `mcserver doctor` muestra estados como:

```text
BDS: none
PowerNukkitX: none
nexora-practice: faltante
nexora-bedwars: faltante
nexora-skywars: faltante
```

No hace falta reinstalar ni borrar `/opt/bedrock-network`.

## Recuperación

```bash
sudo mcserver update project
sudo mcserver bootstrap
```

`bootstrap` es idempotente y realiza:

1. normalización de permisos del código;
2. instalación/comprobación de dependencias;
3. instalación de unidades systemd;
4. firewall local;
5. BDS oficial para Lobby/Survival;
6. PowerNukkitX para PvP/BedWars/SkyWars;
7. compilación e instalación de los tres plugins Nexora;
8. preparación del mundo del Lobby y su behavior pack;
9. arranque de Lobby, PvP, BedWars y SkyWars;
10. arranque de Survival solo si el mundo ya fue importado;
11. validación de plugins, minijuegos, puertos y seguridad del Survival.

## Firewall de la imagen Oracle

Algunas imágenes de Oracle traen una regla `REJECT` al final de `INPUT` aunque UFW esté desactivado. `mcserver firewall apply` crea una cadena propia llamada:

```text
BEDROCK-NETWORK
```

y coloca el salto a esa cadena antes del `REJECT` existente.

Permite únicamente:

```text
TCP 80
TCP 443
UDP 19132
UDP 19133
UDP 19134
UDP 19135
UDP 19136
```

No modifica TCP/22.

Si UFW está activo, se usan reglas UFW en lugar de la cadena administrada directamente.

Las reglas iptables se guardan mediante `netfilter-persistent` para sobrevivir reinicios.

Estado:

```bash
sudo mcserver firewall status
```

Aplicar/reparar:

```bash
sudo mcserver firewall apply
```

## Security List / NSG de Oracle

El firewall local no puede cambiar las reglas de red de Oracle Cloud. En la consola de Oracle, la VNIC/subred debe permitir también:

```text
TCP 80,443
UDP 19132-19136
```

No es necesario publicar TCP/8080. Nginx recibe tráfico en 80/443 y lo reenvía internamente al backend web.

## Survival

Si existe:

```text
/opt/bedrock-network/state/survival-pending-import
```

`bootstrap` mantiene Survival detenido. No genera un mundo vacío.

Después de configurar HTTPS puedes importar desde Android en:

```text
https://minecraftnexora.duckdns.org/admin.html
```

O desde terminal:

```bash
sudo mcserver import-survival /ruta/Mundo.zip
```

## Validación final

```bash
sudo mcserver plugins doctor
sudo mcserver minigames status
sudo mcserver firewall status
sudo mcserver network verify
sudo mcserver doctor
```

El estado esperado antes de importar Survival es:

```text
Lobby      ONLINE
Survival   pendiente de importación
PvP        ONLINE
BedWars    ONLINE
SkyWars    ONLINE
Web        active
```

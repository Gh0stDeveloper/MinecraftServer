# Despliegue de MinecraftServer en la VPS

Configuración prevista:

- IPv4 pública: `147.224.196.17`
- Dominio: `minecraftserver.duckdns.org`
- Minecraft/Lobby: UDP `19132`
- Survival: UDP `19133`
- PvP: UDP `19134`
- BedWars: UDP `19135`
- SkyWars: UDP `19136`
- Web de estado: TCP `8080`

## 1. DuckDNS

En DuckDNS crea o actualiza el hostname `minecraftserver` para que apunte a:

```text
147.224.196.17
```

No guardes el token de DuckDNS en el repositorio. El proyecto no necesita el token para ejecutar Minecraft; solo necesita que el registro DNS ya resuelva correctamente.

Comprueba desde la VPS:

```bash
getent ahostsv4 minecraftserver.duckdns.org
```

La salida debe incluir exactamente `147.224.196.17`.

## 2. Primera instalación

El instalador ya conoce la IP y el dominio del despliegue. Puedes ejecutar:

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash
```

También puedes expresarlo de forma explícita:

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash -s -- \
  --public-ip 147.224.196.17 \
  --domain minecraftserver.duckdns.org
```

Comportamiento:

1. si `minecraftserver.duckdns.org` ya resuelve a `147.224.196.17`, `PUBLIC_HOST` usa el dominio;
2. si el DNS todavía no coincide, `PUBLIC_HOST` usa `147.224.196.17` como fallback;
3. nunca cambia automáticamente a un dominio que apunte a otra IP.

## 3. Comprobar red

```bash
sudo mcserver network status
sudo mcserver network verify
```

`verify` comprueba:

- resolución IPv4 del dominio;
- que el DNS coincide con la IP esperada;
- listeners UDP 19132–19136;
- listener TCP de la web.

Cuando DuckDNS ya sea correcto:

```bash
sudo mcserver network use-domain
```

El comando se negará a cambiar si el dominio no resuelve a `147.224.196.17`.

Para volver a la IP:

```bash
sudo mcserver network use-ip
```

Ambos comandos regeneran la configuración del lobby para que las transferencias usen el host seleccionado.

## 4. Firewall del proveedor

El instalador configura UFW dentro de Ubuntu, pero el proveedor de la VPS también puede tener un firewall externo o Security Group. Deben permitirse como mínimo:

```text
UDP 19132
UDP 19133
UDP 19134
UDP 19135
UDP 19136
TCP 8080
TCP 80
TCP 443
TCP 22
```

`22/tcp` se conserva para SSH. No reemplaza ni reutiliza el puerto SSH para Minecraft.

## 5. Web, dominio y HTTPS

Configurar Nginx:

```bash
sudo mcserver web domain minecraftserver.duckdns.org
```

Después de que DNS funcione correctamente, configura HTTPS con un correo real:

```bash
sudo mcserver web https minecraftserver.duckdns.org TU_CORREO
```

No intentes solicitar el certificado antes de que el dominio resuelva públicamente a la VPS.

## 6. Survival

El Survival se importa aparte y sigue en BDS oficial:

```bash
sudo mcserver import-survival "/ruta/al/Mundo"
```

El importador mantiene `level.dat` sin editar y valida `allow-cheats=false`.

## 7. Diagnóstico final

```bash
sudo mcserver status
sudo mcserver plugins doctor
sudo mcserver minigames status
sudo mcserver network verify
sudo mcserver doctor
```

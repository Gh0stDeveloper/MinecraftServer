<div align="center">

# 📚 Nexora Bedrock Network · Documentación

**Guías de despliegue, recuperación, runtime y administración web.**

![Minecraft](https://img.shields.io/badge/Minecraft-Bedrock-62B47A?style=flat-square)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?style=flat-square&logo=ubuntu&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-5%2B-4EAA25?style=flat-square&logo=gnubash&logoColor=white)
![Java](https://img.shields.io/badge/Java-21-ED8B00?style=flat-square&logo=openjdk&logoColor=white)

[⬅️ Volver al proyecto](../README.md)

</div>

---

## 🧭 Índice rápido

| Documento | Para qué sirve |
|---|---|
| [🌐 Panel web administrativo](WEB_ADMIN.md) | Configurar HTTPS, token administrativo y subir/importar Survival desde navegador o Android. |
| [☁️ Recuperación en Oracle Cloud](ORACLE_RECOVERY.md) | Reparar una instalación incompleta, firewall local y reglas Security List/NSG. |
| [⚙️ Runtime PowerNukkitX](PNX_RUNTIME.md) | Entender el snapshot, fallback reproducible, Java 21 y validación del JAR ejecutable. |

## 🧱 Arquitectura resumida

```text
Jugador Bedrock
      │
      └── UDP/19132 ──► Gateway RakNet ──► Lobby · BDS local :20132
                           │
                           ├── UDP/19133 ──► Survival · BDS local :20133
                           ├── UDP/19134 ──► PvP · PowerNukkitX
                           ├── UDP/19135 ──► BedWars · PowerNukkitX
                           └── UDP/19136 ──► SkyWars · PowerNukkitX

Internet ── TCP/80,443 ──► Nginx ──► Web interno :8080
```

> [!IMPORTANT]
> **Survival permanece aislado en BDS oficial** y no recibe los plugins de PowerNukkitX. El proyecto mantiene `allow-cheats=false` y no inicia Survival hasta que el mundo real haya sido importado.

## 🚀 Instalación

```bash
curl -fsSL https://raw.githubusercontent.com/Gh0stDeveloper/MinecraftServer/main/install.sh | sudo bash
```

El asistente detecta la IPv4 pública, solicita un dominio, recomienda DuckDNS si no tienes uno y prepara los runtimes, minijuegos, firewall y panel web.

## 🩺 Recuperación rápida

```bash
sudo mcserver update project
sudo mcserver bootstrap
```

Después valida:

```bash
sudo mcserver status
sudo mcserver plugins doctor
sudo mcserver minigames status
sudo mcserver network verify
sudo mcserver doctor
```

## 🧰 Comandos esenciales

| Acción | Comando |
|---|---|
| Estado general | `mcserver status` |
| Diagnóstico | `sudo mcserver doctor` |
| Bootstrap/reparación | `sudo mcserver bootstrap` |
| Verificar red | `sudo mcserver network verify` |
| Firewall local | `sudo mcserver firewall status` |
| Logs del Lobby | `sudo mcserver logs lobby` |
| Token del panel | `sudo mcserver web admin-token` |
| Importar Survival | `sudo mcserver import-survival /ruta/Mundo.zip` |

---

<div align="center">

**Nexora Bedrock Network** · self-hosted · reproducible · orientado a VPS Ubuntu

</div>

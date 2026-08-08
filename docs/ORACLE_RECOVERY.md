<div align="center">

# ☁️ Recuperación en Oracle Cloud

**Repara una instalación incompleta sin reinstalar ni borrar tus datos.**

![Oracle](https://img.shields.io/badge/Oracle-Cloud-F80000?style=flat-square&logo=oracle&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-VPS-E95420?style=flat-square&logo=ubuntu&logoColor=white)
![iptables](https://img.shields.io/badge/Firewall-iptables%20%7C%20UFW-7B61FF?style=flat-square)

[⬅️ Documentación](README.md) · [🏠 Proyecto](../README.md)

</div>

---

## 🩺 ¿Cuándo usar esta guía?

Cuando `mcserver doctor` o `mcserver status` muestre una instalación parcial, por ejemplo:

```text
BDS: none
PowerNukkitX: none
nexora-practice: faltante
nexora-bedwars: faltante
nexora-skywars: faltante
```

> [!IMPORTANT]
> **No reinstales y no borres `/opt/bedrock-network`.** El bootstrap está diseñado para completar una instalación existente y preservar los datos persistentes.

## ♻️ Recuperación principal

```bash
sudo mcserver update project
sudo mcserver bootstrap
```

`bootstrap` comprueba o completa:

- permisos y dependencias;
- unidades systemd;
- firewall local;
- BDS para Lobby/Survival;
- PowerNukkitX para minijuegos;
- plugins Nexora;
- addon y mundo del Lobby;
- PvP, BedWars y SkyWars;
- servicios web;
- sockets locales y seguridad de Survival.

## 🧱 Firewall local de Oracle

Algunas imágenes de Oracle incluyen un `REJECT` al final de `INPUT` aunque UFW esté desactivado.

Nexora crea una cadena administrada:

```text
BEDROCK-NETWORK
```

Permisos administrados:

| Protocolo | Puerto | Uso |
|---|---:|---|
| TCP | `80` | HTTP / Certbot / redirección |
| TCP | `443` | HTTPS |
| UDP | `19132` | Lobby |
| UDP | `19133` | Survival |
| UDP | `19134` | PvP |
| UDP | `19135` | BedWars |
| UDP | `19136` | SkyWars |

Nexora **no modifica TCP/22**.

```bash
sudo mcserver firewall status
sudo mcserver firewall apply
```

Las reglas se persisten con `netfilter-persistent` cuando UFW no está activo.

## 🌍 Security List / NSG

> [!WARNING]
> El firewall del sistema operativo y el firewall de Oracle Cloud son capas distintas.

En la consola de Oracle debes permitir también:

```text
TCP 80,443
UDP 19132-19136
```

No necesitas publicar `TCP/8080`: Nginx recibe `80/443` y reenvía internamente al backend.

## 🌲 Survival

Mientras exista:

```text
/opt/bedrock-network/state/survival-pending-import
```

Survival permanece detenido para evitar crear un mundo vacío accidentalmente.

Importación CLI:

```bash
sudo mcserver import-survival /ruta/Mundo.zip
```

O desde el panel HTTPS:

```text
https://TU_DOMINIO/admin.html
```

## ✅ Validación final

```bash
sudo mcserver status
sudo mcserver plugins doctor
sudo mcserver minigames status
sudo mcserver firewall status
sudo mcserver network verify
sudo mcserver doctor
```

Estado esperado antes de importar Survival:

```text
Lobby      ONLINE
Survival   pendiente de importación
PvP        ONLINE
BedWars    ONLINE
SkyWars    ONLINE
Web        active
```

## 🔍 Diagnóstico adicional

```bash
sudo mcserver logs lobby
sudo mcserver logs pvp
sudo mcserver logs bedwars
sudo mcserver logs skywars
```

Y para ver listeners locales:

```bash
sudo ss -lunp
sudo ss -ltnp
```

---

<div align="center">

**Oracle Cloud + Nexora:** firewall local administrado, reglas cloud explícitas y recuperación idempotente.

</div>

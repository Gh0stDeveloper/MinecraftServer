<div align="center">

# 🌐 Panel Web Administrativo

**Importa y administra Survival desde Android o cualquier navegador sin SFTP.**

![HTTPS](https://img.shields.io/badge/HTTPS-required-6C63FF?style=flat-square&logo=letsencrypt&logoColor=white)
![Security](https://img.shields.io/badge/Admin-SHA--256-FF6B81?style=flat-square)
![Upload](https://img.shields.io/badge/Upload-ZIP%20%7C%20MCWORLD-00B8D9?style=flat-square)

[⬅️ Documentación](README.md) · [🏠 Proyecto](../README.md)

</div>

---

## 🚀 Acceso

Con dominio y HTTPS configurados:

```text
https://TU_DOMINIO/admin.html
```

> [!IMPORTANT]
> La API administrativa rechaza peticiones públicas por HTTP. Usa HTTPS antes de exponer el panel a Internet.

## 🔑 Crear o cambiar el token

```bash
sudo mcserver web admin-token
```

El token se muestra **una sola vez**. En disco solo queda su hash SHA-256:

```text
/opt/bedrock-network/config/web-admin.token.sha256
```

Permisos esperados:

```text
owner: root
 group: bedrock
 mode : 0640
```

## 📦 Subir e importar Survival

1. Abre `https://TU_DOMINIO/admin.html`.
2. Introduce el token y pulsa **Validar**.
3. Selecciona un archivo `.zip` o `.mcworld`.
4. Pulsa **Subir e importar Survival**.
5. Sigue el progreso de subida e importación desde la misma página.

Límite predeterminado:

```ini
WEB_MAX_UPLOAD_MB=4096
```

Nginx usa el mismo límite y desactiva el buffering de la petición para evitar duplicar innecesariamente archivos grandes en caché.

## 🔐 Modelo de seguridad

```text
Navegador / HTTPS
       │
       ▼
web/server.py  (usuario bedrock)
       │
       ├── uploads/<id>.zip
       └── uploads/requests/<id>.json
                 │
                 ▼
            systemd.path
                 │
                 ▼
bedrock-survival-import.service  (root)
                 │
                 ▼
       process-web-import.sh
                 │
                 ▼
         import-survival.sh
```

El worker privilegiado:

- serializa operaciones con el lock global de `mcserver`;
- valida ID, ruta, tamaño y SHA-256;
- reutiliza las defensas de ZIP/MCWORLD del importador CLI;
- rechaza archivos ambiguos o con rutas inseguras;
- crea backup del mundo anterior;
- conserva `level.dat`;
- fuerza Survival a BDS;
- mantiene `allow-cheats=false` y `force-gamemode=false`;
- elimina el archivo temporal al finalizar.

> [!NOTE]
> Los backups permanecen en `/opt/bedrock-network/backups/imports/` aunque el archivo temporal de subida sea eliminado.

## 🦆 Dominio gratuito con DuckDNS

Si no tienes dominio, puedes crear un subdominio gratuito en:

**https://www.duckdns.org/**

Ejemplo:

```text
miservidor.duckdns.org → 203.0.113.10
```

Cuando el DNS ya apunte a la VPS:

```bash
sudo mcserver network use-domain
```

## 🔒 Activar Nginx y HTTPS

```bash
sudo mcserver web domain TU_DOMINIO
sudo mcserver web https TU_DOMINIO TU_CORREO
```

Después valida:

```bash
sudo mcserver web status
sudo mcserver network verify
```

## 🩺 Recuperación

Si el panel o worker quedaron incompletos:

```bash
sudo mcserver update project
sudo mcserver bootstrap
```

Después vuelve a generar el token si es necesario:

```bash
sudo mcserver web admin-token
```

---

<div align="center">

**Survival permanece protegido y detenido hasta que la importación real se completa.**

</div>

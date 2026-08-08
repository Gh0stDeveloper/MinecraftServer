# Recuperación de permisos de mcserver

Si una instalación anterior muestra `Permission denied` al ejecutar un script de `/opt/bedrock-network/app/scripts`, aplica una sola vez:

```bash
sudo chmod 0755 /opt/bedrock-network /opt/bedrock-network/app /opt/bedrock-network/app/scripts
sudo find /opt/bedrock-network/app/scripts -type f -name '*.sh' -exec chmod 0755 {} +
sudo chmod 0755 /opt/bedrock-network/app/scripts/bds-resolver.py
```

Después actualiza el proyecto otra vez:

```bash
sudo mcserver update project
```

Las versiones nuevas normalizan estos permisos automáticamente.

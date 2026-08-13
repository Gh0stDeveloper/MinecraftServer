<div align="center">

# ⚙️ PowerNukkitX Runtime

**Política de instalación, fallback reproducible y validación del servidor ejecutable.**

![PowerNukkitX](https://img.shields.io/badge/PowerNukkitX-3.0.2-7B61FF?style=flat-square)
![Java](https://img.shields.io/badge/Java-21-ED8B00?style=flat-square&logo=openjdk&logoColor=white)
![Gradle](https://img.shields.io/badge/Gradle-shadowJar-02303A?style=flat-square&logo=gradle&logoColor=white)

[⬅️ Documentación](README.md) · [🏠 Proyecto](../README.md)

</div>

---

## 🎯 Objetivo

PvP, BedWars y SkyWars usan **PowerNukkitX**. Lobby y Survival permanecen en Bedrock Dedicated Server oficial.

El updater debe poder recuperar una instalación incluso cuando upstream retire temporalmente el asset `snapshot`.

## 📦 Política de origen

Nexora intenta primero el snapshot oficial publicado por PowerNukkitX:

```text
https://github.com/PowerNukkitX/PowerNukkitX/releases/download/snapshot/powernukkitx-shaded.jar
```

Si el asset existe y es válido, se instala directamente.

Si upstream devuelve `404` o el asset no está disponible:

```text
snapshot oficial
      │
      └── no disponible
              │
              ▼
commit oficial fijado
              │
              ▼
Gradle Wrapper upstream
              │
              ▼
shadowJar
              │
              ▼
validación del JAR
              │
              ▼
release activa
```

## 🔒 Fallback reproducible

El fallback exige:

- repositorio oficial `PowerNukkitX/PowerNukkitX`;
- commit fijado con SHA completo de 40 caracteres;
- versión PowerNukkitX esperada;
- versión Bedrock esperada;
- Java 21+;
- Gradle Wrapper del propio upstream;
- tarea `shadowJar`;
- JAR final con clase `org.powernukkitx.JarStart`;
- `META-INF/MANIFEST.MF` con `Main-Class: org.powernukkitx.JarStart`.

> [!IMPORTANT]
> Nexora no sustituye el servidor por un JAR Maven "thin". El runtime necesita sus dependencias empaquetadas para funcionar de forma autónoma.

## ✅ Validación robusta del JAR

El JAR se inspecciona directamente como ZIP con Python.

Esto evita falsos negativos provocados por patrones del tipo:

```bash
jar tf archivo.jar | grep -q ...
```

cuando `set -o pipefail` está activo y el productor recibe `SIGPIPE` después de que `grep -q` encuentre la clase buscada.

La validación actual comprueba:

```text
org/powernukkitx/JarStart.class
META-INF/MANIFEST.MF
Main-Class: org.powernukkitx.JarStart
```

## ♻️ Reutilización

Si ya existe una release construida desde el mismo `PNX_SOURCE_REF` y el JAR sigue siendo válido, `bootstrap` la reutiliza.

Así se evita recompilar Gradle en cada ejecución mientras el snapshot upstream siga ausente.

## 🩺 Comandos útiles

### Protección de puertos al arrancar

Cada inicio de PowerNukkitX elimina `nukkit.yml`, valida que `settings.port` en
`pnx.yml` coincida con el `server-port` administrado y corrige el valor si es
necesario. Además, una salida inesperada con código `0` se convierte en fallo
para que systemd la reinicie y no deje la instancia como `inactive (dead)`.

```bash
sudo mcserver update pnx
sudo mcserver bootstrap
sudo mcserver status
sudo mcserver doctor
```

Logs técnicos de tareas compactadas:

```text
/var/log/mcserver/tasks.log
```

Modo completo:

```bash
sudo MCSERVER_VERBOSE=1 mcserver bootstrap
```

## 🧪 Cobertura CI

GitHub Actions valida:

- acceso al commit fijado;
- metadata de versión;
- compatibilidad Bedrock;
- Java 21;
- construcción de plugins Nexora;
- JAR válido e inválidos sintéticos;
- reutilización y preparación del runtime.

---

<div align="center">

**El objetivo no es solo instalar PowerNukkitX: es poder reconstruir el runtime de forma verificable cuando upstream cambie su distribución.**

</div>

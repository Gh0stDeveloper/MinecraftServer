# Isla flotante del Lobby

El lobby de BedrockNetwork está diseñado como un **hub flotante** a gran altura, similar al patrón visual utilizado por redes de minijuegos: una plaza central y cuatro plataformas periféricas conectadas por caminos.

## Distribución

- Centro: spawn y selector principal.
- Norte: Survival.
- Este: PvP.
- Sur: BedWars.
- Oeste: SkyWars.
- Altura base: Y=160.

El generador crea una isla circular por capas de grass/dirt/stone/deepslate, una plaza de cuarzo, caminos, cuatro plataformas de andesita e iluminación empotrada.

## Construcción inicial

1. Arranca el lobby con el Behavior Pack instalado.
2. Desde consola da temporalmente la etiqueta de administrador al jugador que construirá el hub:

```text
tag "TuGamertag" add network.admin
```

3. Entra al lobby y escribe:

```text
!buildhub
```

4. Espera el mensaje `Isla del lobby construida`.
5. Crea/coloca los NPC con estos nombres exactos:
   - `Survival` en la plataforma Norte.
   - `PvP` en la plataforma Este.
   - `BedWars` en la plataforma Sur.
   - `SkyWars` en la plataforma Oeste.
6. Cuando termines, puedes retirar el permiso:

```text
tag "TuGamertag" remove network.admin
```

`!buildhub` no se ejecuta automáticamente para evitar reconstrucciones accidentales sobre un lobby personalizado. Es una base reproducible que después puede decorarse con estructuras, árboles, hologramas, portales, partículas y otros elementos visuales.

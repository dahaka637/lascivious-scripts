# Subir Escaleras — Project Zomboid B42.20

Añade una opción de **clic derecho → "Subir por la escalera" / "Bajar por la escalera"**
sobre cualquier objeto trepable del juego (escaleras metálicas, escaleras de obra,
escaleras de alcantarilla, cuerdas de sábanas… y las que colocas tú mismo).

## Cómo activarlo

1. Suscríbete en el Workshop, o copia la carpeta del mod en
   `%USERPROFILE%\Zomboid\mods\`.
2. Menú principal → **Mods** → activa **Subir Escaleras**. En una partida ya
   empezada hay que activarlo desde el botón *Mods* de la pantalla de carga.
3. Carga la partida. Ponte al lado de la escalera (o encima de su casilla),
   clic derecho sobre ella → *Subir por la escalera*.

Para **bajar** no hace falta ver la escalera: ponte arriba, a un cuadro o menos
del hueco por el que sube, y haz clic derecho en el suelo → *Bajar por la
escalera*. El mod busca la escalera un nivel por debajo de ti.

## Con el teclado

**Mantén pulsada la E** junto a una escalera y sube o baja por ella sin abrir el
menú. Sube si la escalera está a tu altura, baja si está justo debajo.

Se exige mantenerla, y no un toque, porque `E` es la tecla *Interact* del juego
(`keyBinding.lua:32`): con un toque abrirías a la vez la puerta o la ventana que
tengas al lado. El retardo son `SubirEscaleras.holdTicks` fotogramas — 20 por
defecto, algo menos de medio segundo. Una sola subida por pulsación: para repetir
hay que soltar y volver a pulsar.

Rebindeable en **Opciones → Controles → Subir Escaleras**. El nombre visible sale
de `getText("UI_optionscreen_binding_" .. value)` (`MainOptions.lua:2182`), por
eso el identificador es ASCII y el texto está en `media/lua/shared/Translate/`.

## Cómo funciona

- Detecta la escalera leyendo las propiedades del sprite en caliente, en este
  orden: banderas `climbSheetN/S/E/W` del motor → propiedades `ladderN/S/E/W`
  del tiledef → lista de sprites conocidos → `CustomName=Ladder` o un sprite
  cuyo nombre contenga "ladder". Los dos primeros pasos cubren cualquier
  escalera, del juego base **o de otro mod**, sin tener que listarla.
- La letra de `ladder*` es el lado por el que se sale de la escalera. Cuando no
  se conoce la dirección, se prueban los cuatro lados.
- Si el juego ya sabe trepar ahí (`canClimbSheetRope`), usa la animación nativa.
- Si no, ejecuta una acción temporizada y mueve al personaje al nivel de arriba
  o de abajo.

## La animación (y por qué no es la de trepar cuerdas)

Se usa `setActionAnim("Loot")` con `LootPosition` en `High` al subir y `Low` al
bajar. Es la capa `actions`, que entra como **substate** cuando
`IsPerformingAnAction` es true y no toca la física del personaje.

La animación real de trepar (`Bob_ClimbRope`) **no sirve aquí**. Se entra en ella
con `reportEvent("EventClimbRope")` y se mantiene con la variable `ClimbRope` a
true, pero `climbrope` no es una capa de animación: es un estado completo del
personaje. Con `ClimbRope` activa el motor deja de aplicar la colisión con el
suelo — así es como se atraviesan los pisos al trepar de verdad — y sin una
cuerda real el personaje se hunde, se aleja de la casilla de salida, `isValid()`
falla y la acción se cancela sin llegar a moverte.

Probado y descartado. Para usarla haría falta que el motor te metiera en
`ClimbSheetRopeState`, y eso exige que la casilla tenga las banderas
`climbSheet*` que precisamente le faltan a estas escaleras.

## Si la opción sale en gris

El mod comprueba que arriba haya un sitio donde pisar. Los dos motivos habituales:

- **"No hay ningún nivel cargado encima"** → no existe casilla en z+1.
- **"Arriba no hay suelo donde pisar"** → la escalera muere contra el techo.
  Una escalera necesita un destino: un tejado o un suelo construido encima.
  Constrúyete un suelo de madera en el nivel superior, justo sobre la casilla
  de la escalera, y la opción se activa.

## Si tu escalera no se detecta

Abre `42/media/lua/client/SubirEscaleras/SE_Utils.lua` y pon:

```lua
SubirEscaleras.debug = true
```

Recarga la partida, clic derecho sobre la escalera → *[Escaleras] Volcar info a
la consola*. En `%USERPROFILE%\Zomboid\console.txt` aparecerá el nombre del
sprite y sus propiedades.

## Ajustes

En `SE_Utils.lua`:

| Variable | Por defecto | Qué hace |
|---|---|---|
| `SubirEscaleras.debug` | `false` | Opción de diagnóstico en el menú |
| `SubirEscaleras.climbTime` | `80` | Duración de la acción |
| `SubirEscaleras.enduranceCost` | `0.03` | Resistencia gastada por tramo |

## Estructura

```
SubirEscaleras/
├── mod.info
├── README.md
└── 42/
    ├── mod.info
    └── media/lua/
        ├── client/SubirEscaleras/
        │   ├── SE_Utils.lua        (detección, validación, movimiento)
        │   ├── SE_ClimbAction.lua  (acción temporizada)
        │   ├── SE_ContextMenu.lua  (menú de clic derecho)
        │   ├── SE_Keybind.lua      (mantener E)
        │   └── SE_Sync.lua         (recoloca a los jugadores ajenos en MP)
        ├── server/
        │   └── SubirEscaleras_Server.lua  (valida y difunde en MP)
        └── shared/Translate/       (EN, ES, ES_MX, ES_CL)
```

## Animaciones: lo que sabemos, comprobado

**Un mod SÍ puede añadir clips de animación propios.** Comprobado copiando
`Bob_ClimbFence.x` dentro del mod con el `AnimationSet` renombrado: el juego lo
cargó y lo reprodujo.

Ojo, porque la pista era engañosa: el juego recorre en cada mod solo
`media/AnimSets` y `media/actiongroups` (se ve en el log, un `NoSuchFileException`
por carpeta). No recorre `media/anims_X`, pero los clips que hay ahí los carga
igualmente por otra vía.

| Dato | Valor |
|---|---|
| Formato | DirectX `.x`, **texto plano** (`xof 0303txt 0032`) |
| Ruta en el mod | `42/media/anims_X/Bob/<archivo>.x` |
| Lo que enlaza | El nombre del `AnimationSet` **dentro** del archivo, no el del archivo |
| Esqueleto | `Bip01_*` (Biped de 3ds Max) + `Dummy01`, 68 huesos |
| Claves | `R` cuaternión (w,x,y,z), `S` escala, `T` traslación |
| Duración | Ticks; los clips del juego van de 0 a 4800 |
| Esqueleto base | `models_X/Skinned/Male_Skeleton.x`, `MaleBody.x`, `FemaleBody.x` |

Para el esqueleto del jugador solo existe un clip de trepar, `Bob_ClimbRope`.
`Rac_ClimbUp` / `Rac_ClimbDown` son del mapache, otro esqueleto.

## Multijugador

En PZ la posición de un jugador es autoritativa **en su propio cliente**, y el
resto la interpola de los paquetes de movimiento. Un cambio de nivel no viaja
por ese canal: sin nada más, el que trepa se ve subir y los demás le siguen
viendo abajo andando. Comprobado en un servidor real.

Por eso hacen falta tres pasos:

1. El cliente se mueve a sí mismo, **y además** avisa al servidor con
   `sendClientCommand`. No se limita a avisar: si el servidor ignorase la orden,
   el jugador se quedaría clavado. Esto ya pasó en la 1.8 y hubo que revertirlo.
2. El servidor valida el destino — rechaza saltos de más de 2 casillas en
   horizontal u 8 niveles — y mueve su copia del jugador.
3. El servidor difunde con `sendServerCommand`, y cada cliente recoloca a mano
   al jugador ajeno (`SE_Sync.lua`).

La validación del paso 2 no es decorativa: `OnClientCommand` lo puede mandar
cualquier cliente modificado, y sin límites esto sería un teletransporte libre.

## El fallo del juego base que corrige

Sacando los tiledefs de `newtiledefinitions.tiles` (B42.20), varias escaleras
llevan la propiedad `ladderN`/`ladderW` pero **no** la bandera `climbSheetN`/
`climbSheetW`, que es la que mira el motor para dejarte trepar:

| Sprite | `ladder*` | `climbSheet*` |
|---|---|---|
| `industry_railroad_05_36` (mira al este) | sí | **sí** |
| `industry_railroad_05_37` (mira al sur) | sí | **no** |
| `location_sewer_01_32/33/48/49` | sí | **no** |
| `carpentry_02_84/85/86/87` | sí | **no** |
| `advertising_01_6/14` | sí | **no** |

Sin esa bandera el motor no las considera trepables. Se intentó añadirla en
caliente con `PropertyContainer:Set`, pero esa API no está expuesta a Lua en
B42.20 y solo generaba errores. Por eso el mod no toca los sprites: reconoce
las escaleras por nombre (`SubirEscaleras.ladderSprites`) y mueve al personaje
él mismo.

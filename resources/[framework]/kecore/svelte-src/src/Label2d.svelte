<script lang="ts">
import { fade } from 'svelte/transition'
import { parseMarkup } from './markup'
import { fontFamily } from './fonts'
import type { LabelData } from './types'

let { data }: { data: LabelData } = $props()

const segments = $derived(parseMarkup(data.text))

// El texto sin los tramos, para la capa del contorno: ahí no van los colores (ver el bloque de
// estilos, .label__stroke). Ojo: nada de escribir la etiqueta de estilos entre signos de menor y
// mayor en un comentario de este archivo — el preprocesador la busca con una expresión regular, se
// cree que el bloque empieza AHÍ y deja de compilar el SCSS sin decir nada.
const plain = $derived(segments.map(s => s.text).join(''))

// `x` es el punto donde se ANCLA el texto, no su esquina: centrado tira del bloque medio ancho a la
// izquierda y alineado a la derecha lo tira entero. Es lo que hacía `SetTextCentre(true)` en el
// DrawText de antes, y por lo mismo `y` sigue siendo el borde de ARRIBA del texto y no su centro:
// así los avisos caen donde caían y ninguna de las llamadas que ya existen se mueve de sitio.
const SHIFT: Record<string, string> = { center: '-50%', left: '0', right: '-100%' }
</script>

<!-- El `--label-stroke` va en el atributo `style` y no en una directiva `style:` porque una
     propiedad personalizada necesita `setProperty`; el resto sí son directivas. -->
<div
    class="label"
    style="--label-stroke: {data.outlineWidth / 10}rem {data.outlineColor}"
    style:left="{data.x * 100}%"
    style:top="{data.y * 100}%"
    style:transform="translateX({SHIFT[data.align] ?? '-50%'})"
    style:color={data.color}
    style:font-family={fontFamily(data.font)}
    style:font-size="{data.size / 10}rem"
    style:font-weight={data.weight}
    style:text-align={data.align}
    style:text-shadow={data.shadow ? '0 0.1rem 0.3rem rgba(0, 0, 0, 0.9)' : 'none'}
    in:fade={{ duration: 120 }}
    out:fade={{ duration: 160 }}
>
    {#if data.outline}<span class="label__stroke" aria-hidden="true">{plain}</span>{/if}<!--
    Los tramos van pegados entre sí y a la etiqueta a propósito: con `white-space: pre-wrap`
    cualquier salto de línea de esta plantilla saldría impreso en pantalla. El hueco de arriba sí
    vale: un nodo de texto en blanco dentro de un grid no se pinta.
    --><span class="label__fill">{#each segments as segment}<span style:color={segment.color}>{segment.text}</span>{/each}</span>
</div>

<style lang="scss">
.label{
    position: fixed;
    // Se ajusta al texto (para que el centrado sea el del texto y no el de la pantalla) pero no se
    // sale: un aviso largo parte de línea en vez de irse por los bordes.
    max-width: 92vw;
    line-height: 1.15;
    letter-spacing: 0.02rem;

    // Las dos capas —contorno debajo, texto encima— en la MISMA celda. El grid es lo que las
    // apila sin posicionar nada a mano: la celda mide lo que mide el texto y las dos caen
    // exactamente encima porque tienen el mismo contenido, la misma fuente y el mismo ancho.
    display: grid;

    > span{
        grid-area: 1 / 1;
        // Respeta el texto tal cual: los saltos de línea (los `\n` y los `~n~`) y los espacios de
        // más, que en varios avisos son a propósito ("[H]  Repostar 40%  ·  $120" separa con dos).
        white-space: pre-wrap;
    }
}

// El contorno se dibuja como una COPIA del texto por debajo, y no con `paint-order: stroke fill`
// sobre una sola capa: eso es soporte reciente de Chromium y el CEF del juego es más viejo (ni
// `color-mix` llega), así que allí el trazo saldría centrado en el borde del glifo y se comería
// media letra — el texto se vería más fino cuanto más grueso el contorno. Con dos capas el trazo
// queda entero por fuera en cualquier versión.
//
// Va PRIMERO en el DOM porque el orden de pintado es el del documento: el relleno se pinta después
// y tapa la mitad interior del trazo.
.label__stroke{
    -webkit-text-stroke: var(--label-stroke);
    // Sin relleno: el color del aviso puede ser semitransparente (`{43ff64d9}` es un 85%), y un
    // relleno opaco debajo se vería a través del de arriba y saldría un color más subido del pedido.
    color: transparent;
    // La sombra la pone la capa de encima; en las dos se pintaría dos veces y saldría más oscura.
    text-shadow: none;
}
</style>

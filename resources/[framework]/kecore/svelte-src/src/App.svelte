<script lang="ts">
// El overlay del framework. Hoy solo pinta los avisos de `kec.label2d`, que llegan desde
// `internal/client/label2d_nui.lua` con `SendNUIMessage`.
import Label2d from './Label2d.svelte'
import type { LabelData, LabelMessage } from './types'

// UN aviso a la vez, igual que el label2d de siempre (hacía `clear()` antes de cada texto): el nuevo
// pisa al que hubiera.
//
// El componente NO se remonta al cambiar de texto —nada de `{#key}`— porque hay avisos que se
// repintan en bucle (el arranque de turbinas del avión manda uno cada 150ms) y volver a montar haría
// que su aparición se viera como un parpadeo. Solo aparece y desaparece de verdad al principio y al
// final, que es donde interesa el fundido.
let label = $state.raw<LabelData | null>(null)

// El temporizador vive AQUÍ y no en Lua: así se apaga solo y el framework se queda sin ningún tick
// por frame para esto (el de antes recorría la lista de textos en un everyTick).
let timer: ReturnType<typeof setTimeout> | undefined

function close() {
    clearTimeout(timer)
    label = null
}

function onMessage(event: MessageEvent) {
    const msg = event.data
    if (!msg || msg.action !== 'label2d') return

    const data = msg.label as LabelMessage
    if (!data) return

    if (data.clear) {
        close()
        return
    }

    // `hide(id)` solo se lleva el aviso si sigue siendo EL SUYO: entre el hide y el show que lo
    // sustituye puede haberse colado un tercero (el motor esconde su "Encendiendo..." justo antes de
    // sacar el "Motor encendido"), y ese no es suyo para taparlo.
    if (data.hide) {
        if (label?.id === data.id) close()
        return
    }

    label = data as LabelData
    clearTimeout(timer)
    timer = setTimeout(close, data.duration)
}
</script>

<!-- El listener se ata y se suelta con el componente; nada de addEventListener a mano. -->
<svelte:window onmessage={onMessage} />

{#if label}
    <Label2d data={label} />
{/if}

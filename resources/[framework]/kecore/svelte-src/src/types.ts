// Lo que manda `internal/client/label2d.lua` por cada aviso. Todos los campos de estilo llegan ya
// resueltos desde el Lua (él aplica sus DEFAULTS), así que aquí no hay valores por defecto que
// puedan discrepar con los suyos: la SPA solo pinta.
//
// `color` y `outlineColor` vienen en `#rrggbbaa`. `x`/`y` son fracciones de pantalla 0..1, las
// mismas que aceptaba el `DrawText` de antes. `size` y `outlineWidth` son píxeles A 1080p: la hoja
// de estilos los pasa a rem para que escalen con la altura de la pantalla.
export type LabelData = {
    id: string
    text: string
    color: string
    duration: number
    x: number
    y: number
    align: 'left' | 'center' | 'right'
    size: number
    font: string
    weight: number
    shadow: boolean
    outline: boolean
    outlineWidth: number
    outlineColor: string
}

// Los mensajes de `hide(id)` y `clear()` viajan por el mismo evento y solo traen la bandera (y el
// id, en el caso del hide): Lua no serializa claves nil, así que el resto de campos no llega.
export type LabelMessage = Partial<LabelData> & { hide?: boolean, clear?: boolean }

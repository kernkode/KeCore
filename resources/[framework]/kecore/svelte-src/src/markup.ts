// Colorear un tramo del texto sin tocar el estilo del aviso: `{rrggbbaa}` (o `{rrggbb}`, con la
// alfa a tope) pinta lo que va DETRÁS, y `{}` vuelve al color base del aviso.
//
//   "hola {43ff64d9}soy yo"          -> "hola " en el color base, "soy yo" en 43ff64 al 85%
//   "{ff4444}error{} y ya está"      -> solo "error" en rojo
//
// Una llave que no encierre 6 u 8 dígitos hexadecimales NO es un token y se queda tal cual, así que
// un texto con llaves de verdad ("{404}") no se rompe.
//
// De paso se traducen los códigos de color de GTA (`~y~`, `~s~`, ...). Ya no los entiende nadie —
// esto es HTML, no un DrawText— y sin traducirlos saldrían impresos en pantalla: hay avisos que los
// llevan escritos y hay textos que vienen del servidor, así que se limpian aquí y no en cada sitio.
const GTA: Record<string, string | null> = {
    r: '#ff4444', g: '#44e06a', b: '#3f9dff', y: '#ffd24a',
    p: '#c58fff', o: '#ff9d3f', c: '#c8c8c8', m: '#8f8f8f',
    u: '#000000', w: '#ffffff',
    // El "vuelve al color normal" de GTA. `null` = al color base del aviso, igual que `{}`.
    s: null
}

export type Segment = { text: string, color?: string }

/** "43ff64d9" | "43ff64" -> "#43ff64d9" */
function toColor(hex: string): string {
    return '#' + (hex.length === 6 ? hex + 'ff' : hex)
}

/**
 * Parte el texto en tramos de color. El primero (y único, si no hay tokens) sale sin `color`: lo
 * pinta el color base del aviso, que es el que decide el Lua.
 */
export function parseMarkup(raw: string): Segment[] {
    // La expresión se crea aquí y no en el módulo a propósito: `exec` en bucle avanza `lastIndex`, y
    // una regex compartida arrastraría la posición de la llamada anterior.
    const token = /\{([0-9a-fA-F]{8}|[0-9a-fA-F]{6})?\}|~(\w)~/g
    const out: Segment[] = []

    let color: string | undefined
    let last = 0
    let match: RegExpExecArray | null

    // Los tramos seguidos del mismo color se juntan en uno: `~s~` seguido de `{}` no tiene por qué
    // dejar dos nodos en el DOM.
    const push = (text: string) => {
        if (!text) return

        const prev = out[out.length - 1]
        if (prev && prev.color === color) prev.text += text
        else out.push({ text, color })
    }

    while ((match = token.exec(raw)) !== null) {
        push(raw.slice(last, match.index))
        last = match.index + match[0].length

        const gta = match[2]

        if (gta === undefined) {
            // `{}` sin dígitos = volver al color base.
            color = match[1] ? toColor(match[1]) : undefined
        } else if (gta === 'n') {
            // El salto de línea de GTA. `white-space: pre-line` en el componente lo respeta.
            push('\n')
        } else {
            // `~h~` (negrita) y compañía no tienen equivalente aquí: se descartan sin tocar el
            // color, que es mejor que dejarlos impresos. Ojo con el `in`: sin él, un código
            // desconocido devolvería undefined y eso significa "vuelve al color base".
            const key = gta.toLowerCase()
            if (key in GTA) color = GTA[key] ?? undefined
        }
    }

    push(raw.slice(last))

    return out
}

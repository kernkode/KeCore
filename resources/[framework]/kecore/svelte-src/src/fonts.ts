// Los nombres cortos que puede pedir un aviso (`{ font = "pricedown" }`) y la familia CSS que les
// toca. Los @font-face están en app.scss.
//
// Un nombre que no esté aquí se pasa TAL CUAL a `font-family`, así que una familia que ya tenga el
// sistema ("Arial") también vale sin tocar este archivo. Añadir una fuente propia son dos pasos: el
// .otf/.ttf en src/assets/fonts, su @font-face en app.scss, y su nombre corto aquí.
const FAMILIES: Record<string, string> = {
    barlow: 'Barlow',
    chalet: 'Chalet London',
    oswald: 'Oswald Regular',
    pricedown: 'Pricedown'
}

// El respaldo va detrás de la elegida y no en su lugar: si el .otf tarda en registrarse, el aviso se
// ve en Arial en vez de no verse.
export function fontFamily(name: string): string {
    return `'${FAMILIES[name] ?? name}', Arial, sans-serif`
}

/**
 * Pasa a WebP las imágenes de los assets de una SPA y borra el original.
 *
 * Por qué: lo que hay en `html/` se lo descarga CADA jugador al entrar (`files { 'html/**' }`),
 * así que ahí el peso es tiempo de carga y subida por jugador. Los 897 renders de vehículos de
 * tab eran PNG en RGBA sin comprimir: 258,5 MB para pintarlos en una tarjeta de 125 px. En WebP
 * q82 a resolución nativa son 31,7 MB, y redimensionados a 384×216 unos 13. El alfa sobrevive
 * (la salida es VP8X+ALPH) y Chromium 103, el del CEF, lee WebP con alfa de sobra.
 *
 * La caja máxima es por destino porque no se ve todo igual: un render en una tarjeta de 125 px
 * no necesita 500 px de alto, pero un fondo a pantalla completa sí quiere 1080p. Medido sobre
 * los PNG de tab: a resolución nativa el 12,2 % del PNG, a ≤512 px el 7,3 %, a ≤384 px el 5,1 %.
 *
 * Uso: `bun scripts/tools/webp-assets.ts [--max=384x216] <dir...>`
 */
import { readdirSync, statSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';

/** q82 es el punto donde deja de notarse en un render sobre fondo transparente. */
const QUALITY = 82;

/** Cuántas a la vez: Bun.Image trabaja fuera del hilo de JS, así que conviene darle cola. */
const BATCH = 8;

const CONVERTIBLE = /\.(png|jpe?g)$/i;

const args = process.argv.slice(2);
const maxArg = args.find((arg) => arg.startsWith('--max='))?.slice('--max='.length);
const max = maxArg?.split('x').map(Number) as [number, number] | undefined;

if (max && (max.length !== 2 || max.some((n) => !Number.isFinite(n)))) {
    console.error('--max espera ANCHOxALTO, por ejemplo --max=384x216');
    process.exit(1);
}

// Los directorios van por argumento y no hay ninguno por defecto: los assets son de cada
// recurso, y este script vive en el framework.
const dirs = args.filter((arg) => !arg.startsWith('--'));

if (dirs.length === 0) {
    console.error('uso: bun scripts/tools/webp-assets.ts [--max=ANCHOxALTO] <dir...>');
    process.exit(1);
}

const mb = (bytes: number): string => `${(bytes / 1048576).toFixed(1)} MB`;

for (const dir of dirs) {
    let names: string[];
    try {
        names = readdirSync(dir).filter((name) => CONVERTIBLE.test(name));
    } catch {
        console.error(`no se pudo leer ${dir}`);
        process.exitCode = 1;
        continue;
    }

    if (names.length === 0) {
        console.log(`${dir}: nada que convertir`);
        continue;
    }

    const started = Date.now();
    let before = 0;
    let after = 0;

    for (let i = 0; i < names.length; i += BATCH) {
        // Cada tarea DEVUELVE sus tamaños en vez de sumarlos: un `total += await ...` dentro de un
        // Promise.all lee `total` antes del await, así que las 8 del lote se pisan entre ellas y el
        // resumen sale 5 veces más optimista que la carpeta real.
        const sizes = await Promise.all(names.slice(i, i + BATCH).map(async (name) => {
            const source = join(dir, name);
            const target = join(dir, name.replace(CONVERTIBLE, '.webp'));

            const sourceSize = statSync(source).size;
            const image = Bun.file(source).image();
            const written = await (max
                ? image.resize(max[0], max[1], { fit: 'inside', withoutEnlargement: true })
                : image
            ).webp({ quality: QUALITY }).write(target);

            // El original se va: si no, se queda en el repo pesando lo mismo que antes.
            unlinkSync(source);

            return [sourceSize, written] as const;
        }));

        for (const [sourceSize, written] of sizes) {
            before += sourceSize;
            after += written;
        }
    }

    const seconds = (Date.now() - started) / 1000;
    console.log(
        `${dir}${max ? ` (≤${max[0]}×${max[1]})` : ''}: ${names.length} imágenes, ` +
        `${mb(before)} → ${mb(after)} (${(after / before * 100).toFixed(1)}%) en ${seconds.toFixed(1)}s`
    );
}

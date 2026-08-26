import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
    build: {
        outDir: '../html',
        emptyOutDir: true,
        // Un solo CSS y sin <link rel="modulepreload">: el CEF sirve esto desde el disco del
        // recurso, así que partir el bundle solo añade peticiones.
        cssCodeSplit: false,
        modulePreload: false,
        reportCompressedSize: false
    },
    plugins: [svelte()],
    resolve: {
        alias: {
            '@': fileURLToPath(new URL('./src', import.meta.url)),
            '@fonts': fileURLToPath(new URL('./src/assets/fonts', import.meta.url))
        }
    },
    base: ''
})

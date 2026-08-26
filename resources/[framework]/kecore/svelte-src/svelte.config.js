import { vitePreprocess } from '@sveltejs/vite-plugin-svelte'

// vitePreprocess deja que Vite se encargue de `lang="ts"` y `lang="scss"` dentro de los
// .svelte: un preprocesador menos que instalar y el mismo pipeline de CSS que el resto.
export default {
    preprocess: vitePreprocess()
}

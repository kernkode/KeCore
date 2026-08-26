import { mount } from 'svelte'
import App from './App.svelte'
import './app.scss'

const app = mount(App, { target: document.getElementById('app')! })

// El CEF no lee una fuente hasta que tiene que pintar un glifo con ella, y aquí no hay nada en
// pantalla hasta el primer aviso: ese glifo caería en el frame del aviso, o sea justo cuando el
// jugador está mirando. Se pide al cargar la página —al arrancar el recurso— y ya está en memoria.
// Mismo motivo (y misma nota) que en el inventario, que precarga las suyas por lo mismo.
//
// En el primer frame y no antes: el <link> del CSS es render-blocking, así que es ahí cuando los
// @font-face ya están registrados y `fonts.load` tiene algo que buscar — llamado antes resolvería
// sin cargar nada y en silencio.
//
// ponytail: solo la de por defecto. Oswald y Pricedown son un `font` que hay que pedir a mano, así
// que se leen la primera vez que alguien las use y no ocupan a quien no las pida.
requestAnimationFrame(() => document.fonts.load('16px "Chalet London"'))

export default app

import { argv } from 'process';
import { downloadAndExtractFXServer } from './updater/utils.ts';

// Modifica la última parte para manejar argumentos CLI
const args: string[] = argv.slice(2); // Elimina los primeros 2 argumentos (node y script path)
const updateTarget: string = args[0] || 'recommended'; // Usa 'recommended' por defecto

if (['latest', 'recommended'].includes(updateTarget) || /^\d+$/.test(updateTarget)) {
    console.log(`Solicitada actualización: ${updateTarget}`);
    await downloadAndExtractFXServer(updateTarget)
        .then(() => console.log('Proceso completado!'))
        .catch(err => console.error('Error crítico:', err));
}
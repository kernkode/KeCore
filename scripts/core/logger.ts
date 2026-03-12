// src/utils/logger.ts
import fs from 'fs/promises';
import chalk from 'chalk';
import { LOG_FILE_PATH } from './configs.ts';

let writeQueue: Promise<void> = Promise.resolve();

// Limpia los códigos de color ANSI para el archivo de log
const cleanAnsiCodes = (text: string): string => text.toString().replace(/\x1b\[[0-9;]*m/g, '');

// Escribe al archivo de log
export function writeToLog(data: string): void {
    writeQueue = writeQueue
        .then(async () => {
            try {
                await fs.mkdir('cache', { recursive: true });
                await fs.appendFile(LOG_FILE_PATH, cleanAnsiCodes(data));
            } catch (error: any) {
                console.error('Error writing to log:', error);
            }
        })
        .catch((error: any) => {
            console.error('Error in write queue:', error);
        });
}

// Interfaz para las opciones de log
interface LogOptions {
    resourceColor?: any;
    textColor?: any;
    resourceName?: string;
}

// Interfaz para el resultado del formateo
interface FormatResult {
    centered: string;
    leftAligned: string;
}

// Función principal para mostrar mensajes
export function log(message: string, {resourceColor = chalk.cyan, textColor = chalk.white, resourceName = 'scripts:start'} = {}): void {
    const formatInFrame = (text: string, totalWidth = 41): FormatResult => {
        // Asegurar que el texto no sea más largo que el espacio disponible
        const truncatedText = text.length > totalWidth - 2 
            ? text.substring(0, totalWidth - 3) + '…' 
            : text;
        
        // Calcular espacios para centrar (opcional)
        const padding = Math.max(0, totalWidth - 2 - truncatedText.length);
        const leftPadding = Math.floor(padding / 2);
        const rightPadding = padding - leftPadding;
        
        // Versión centrada
        const centered = `[${' '.repeat(leftPadding)}${truncatedText}${' '.repeat(rightPadding)}]`;
        
        // Versión alineada a la izquierda (como en tu ejemplo)
        const leftAligned = `[${' '.repeat(Math.max(0, totalWidth - 2 - truncatedText.length))}${truncatedText}]`;
        return { centered, leftAligned };
    }

    const msg = `${formatInFrame(resourceColor.bold(resourceName)).leftAligned} ${textColor.bold(message)}`;
    console.log(msg);
    writeToLog(msg + '\n');
}

// Limpia el archivo de log al inicio
export async function clearLogFile(): Promise<void> {
    try {
        await fs.writeFile(LOG_FILE_PATH, '');
        log('Log file cleared', { resourceColor: chalk.green });
    } catch (error: any) {
        log(`Error clearing log file: ${error.message}`, { resourceColor: chalk.red });
    }
}
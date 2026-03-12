import chalk from 'chalk';
import { log } from './core/logger.ts';
import { startRestAPI } from './core/api.ts';
import { buildManager } from './builder/build-manager.ts';
import { watcher } from './builder/watcher.ts';
import { serverManager } from './core/serverManager.ts';
import { isAvailableUpdate, downloadAndExtractFXServer } from './updater/utils.ts';
import { environment } from './core/configs.ts';

interface UpdateInfo {
    available: boolean;
    current?: string | null;
    latest?: string | null;
    currentVersion?: string;
    latestVersion?: string;
    message?: string;
    versionTransition?: string;
}

/** Función principal que inicia todo el entorno. */
async function main(): Promise<void> {
    console.log(chalk.bold.red(`
         __    __            ______                                
        |  \\  /  \\          /      \\                               
        | $$ /  $$ ______  |  $$$$$$\\  ______    ______    ______  
        | $$/  $$ /      \\ | $$   \\$$ /      \\  /      \\  /      \\ 
        | $$  $$ |  $$$$$$\\| $$      |  $$$$$$\\|  $$$$$$\\|  $$$$$$\\
        | $$$$$\\ | $$    $$| $$   __ | $$  | $$| $$   \\$$| $$    $$
        | $$ \\$$\\| $$$$$$$$| $$__/  \\| $$__/ $$| $$      | $$$$$$$$
        | $$  \\$$ \\$$     \\ \\$$    $$ \\$$    $$| $$       \\$$     \\
         \\$$   \\$$ \\$$$$$$$  \\$$$$$$   \\$$$$$$  \\$$        \\$$$$$$$                                                                                          
    `));

    console.log(
        chalk.bold.hex('#AAAAAA')(`        FXServer `) + 
        chalk.bold.hex('#FF5555')(`Environment & Tools\n`) +
        
        chalk.bold.hex('#AAAAAA')(`        Created by: `) + 
        chalk.bold.hex('#FFAA00')('https://github.com/kernkode\n')
    );
  
    try {
        if (environment.error) {
            log(`❌ Error loading .env: ${environment.error}`);
        } else {
            log('✅ .env loaded successfully');
        }

        const updateInfo: UpdateInfo = await isAvailableUpdate(process.env.FXSERVER!);
        if (updateInfo.available) {
            const transition = `${chalk.bold.hex('#FF5555')(updateInfo.currentVersion)} → ${chalk.bold.hex('#89F336')(updateInfo.latestVersion)}`;
            log(`${chalk.bold.hex('#0077ffff')("📦 Update available:")} ${transition}`);

            await downloadAndExtractFXServer(process.env.FXSERVER!)
                .then(() => log('🎉 Update completed!', { resourceName: 'scripts:start' }))
                .catch((err: Error) => console.error('Critical error:', err));
        }

        await buildManager.runInitialBuilds();
        await serverManager.start();
        await startRestAPI();
        watcher.start();

        // Permitir entrada de comandos a la consola del servidor
        process.stdin.setEncoding('utf8');
        process.stdin.on('data', (data: string) => {
            serverManager.childProcess?.stdin?.write(data);
        });

        // Manejar cierre del proceso
        process.on('SIGINT', async (): Promise<void> => {
            await serverManager.shutdown();
        });

        process.on('SIGTERM', async (): Promise<void> => {
            await serverManager.shutdown();
        });

    } catch (error: unknown) {
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        log(`fatal error: ${errorMessage}`, { resourceColor: chalk.red });
        process.exit(1);
    }
}

main();
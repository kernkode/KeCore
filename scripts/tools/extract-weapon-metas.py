#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
    Extrae de la instalacion local de GTA V todos los .meta de armas y los deja en
    resources/[assets]/weapon_meta/data/, regenerando tambien su fxmanifest.lua.

    Los .rpf del juego van cifrados con NG, asi que la lectura la hace CodeWalker.Core.dll
    (saca las claves del propio GTA5.exe). La DLL es .NET Framework y se carga con pythonnet
    sobre el runtime netfx, sin puente ni servicio de por medio:  pip install pythonnet

    Es el companyero de build-weapon-fx.py: esto saca data/ de los .rpf del juego, ese
    escribe custom/ a partir de data/ + el pack de armas.

    Uso:  bun run tools:weapon-meta
          python scripts/tools/extract-weapon-metas.py --gta 'D:/GTAV'
"""
import argparse, os, re, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))

ap = argparse.ArgumentParser()
ap.add_argument('--gta', default=None,
                help='instalacion de GTA V (por defecto, la que usa FiveM: IVPath de CitizenFX.ini)')
ap.add_argument('--codewalker', default=os.path.expanduser('~/Desktop/ALT-V TOOLS/CodeWalker30_dev47'),
                help='carpeta que contiene CodeWalker.Core.dll')
ap.add_argument('--out', default=os.path.join(REPO, 'resources', '[assets]', 'weapon_meta'),
                help='recurso destino')
args = ap.parse_args()

OUT = os.path.abspath(args.out)
GTA = args.gta
if not GTA:
    ini = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'FiveM', 'FiveM.app', 'CitizenFX.ini')
    if os.path.isfile(ini):
        for line in open(ini, encoding='utf-8', errors='replace'):
            if line.startswith('IVPath='):
                GTA = line[len('IVPath='):].strip()
                break
if not GTA or not os.path.isfile(os.path.join(GTA, 'GTA5.exe')):
    raise SystemExit("No encuentro GTA V (legacy). Pasa --gta 'ruta/al/GTAV'.")

dll = os.path.join(args.codewalker, 'CodeWalker.Core.dll')
if not os.path.isfile(dll):
    raise SystemExit("Falta CodeWalker.Core.dll en '%s'. Pasa --codewalker con la carpeta de "
                     "CodeWalker (github.com/dexyfex/CodeWalker)." % args.codewalker)

build = open(os.path.join(GTA, 'versioninfo.txt'), encoding='utf-8',
             errors='replace').readline().split(' ')[1].strip()
print('GTA V %s  <-  %s' % (build, GTA))

# La DLL es .NET Framework: hay que fijar ese runtime ANTES del primer import de clr.
try:
    from clr_loader import get_netfx
    from pythonnet import set_runtime
except ImportError:
    raise SystemExit('falta pythonnet:  pip install pythonnet')
set_runtime(get_netfx())
import clr
clr.AddReference(dll)
from CodeWalker.GameFiles import GTA5Keys, RpfManager, RpfFileEntry
from System import Action, String

GTA5Keys.LoadFromPath(GTA, None)
noop = Action[String](lambda s: None)
man = RpfManager()
man.Init(GTA, noop, noop, False, False)
print('%d rpf / %d entradas escaneadas' % (man.AllRpfs.Count, man.EntryDict.Count))

# De donde sale cada archivo y quien gana cuando el mismo nombre esta repetido: el juego
# monta el dlc.rpf del DLC y luego el title update lo pisa desde update.rpf\dlc_patch.
RULES = [
    (r'^update\\update\.rpf\\dlc_patch\\([^\\]+)\\',      3, None),
    (r'^update\\x64\\dlcpacks\\([^\\]+)\\dlc\.rpf\\',     2, None),
    (r'^x64w\.rpf\\dlcpacks\\([^\\]+)\\dlc\.rpf\\',       1, None),
    (r'^update\\update\.rpf\\common\\',                   1, 'base'),
    (r'^common\.rpf\\',                                   0, 'base'),
]

best, huerfanos = {}, []
for e in man.EntryDict.Values:
    # vehicleweapon*.meta son armas montadas en vehiculos y shop_weapon.meta es la tienda:
    # ninguno va en este recurso
    name = e.Name.lower()
    if ('weapon' not in name or not name.endswith('.meta')
            or name.startswith('vehicleweapon') or name.startswith('shop_weapon')
            or not isinstance(e, RpfFileEntry)):
        continue
    for pattern, prio, grupo in RULES:
        m = re.match(pattern, e.Path)
        if m:
            break
    else:
        huerfanos.append(e.Path)
        continue

    group = grupo or ('dlc/' + m.group(1))
    key = '%s/%s' % (group, name)
    if key not in best or best[key][0] < prio:
        best[key] = (prio, e, group, name)

for h in huerfanos:
    print('AVISO: ruta sin regla, lo salto: %s' % h)

# data/ es generada entera: se borra, pero solo si dentro no hay nada que no sea .meta.
data_dir = os.path.join(OUT, 'data')
if os.path.isdir(data_dir):
    ajenos = [os.path.join(r, f) for r, _, fs in os.walk(data_dir) for f in fs
              if not f.endswith('.meta')]
    if ajenos:
        raise SystemExit("'%s' tiene archivos que no son .meta, no lo borro: %s"
                         % (data_dir, ', '.join(ajenos)))
    shutil.rmtree(data_dir)

sospechosos = []
for prio, entry, group, name in best.values():
    dst = os.path.join(data_dir, group.replace('/', os.sep), name)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    data = bytes(man.GetFileData(entry.Path))
    open(dst, 'wb').write(data)
    # comprobacion: los .meta de armas son XML de texto; si sale binario (PSO) hay que convertirlo
    if not data[:8].decode('utf-8', 'replace').lstrip(u'\ufeff').startswith('<'):
        sospechosos.append('%s/%s' % (group, name))
if sospechosos:
    raise SystemExit('no son XML (PSO binario?): %s' % ', '.join(sospechosos))

# El recurso NO declara nada de data/: eso es referencia. Lo que se aplica es custom/: el blob
# de las armas base por WEAPONINFO_FILE y los .meta de DLC por WEAPONINFO_FILE_PATCH (el porque
# del reparto y de la subcarpeta, en el comentario que se escribe abajo).
n_custom = sum(1 for r, _, fs in os.walk(os.path.join(OUT, 'custom')) for f in fs
               if f.endswith('.meta'))

lua = [
    "fx_version 'cerulean'",
    "game 'gta5'",
    "lua54 'yes'",
    '',
    "author 'KernKode'",
    "description 'Los .meta de armas vanilla de GTA V " + build + " + los retoques de custom/'",
    '',
    '-- AUTO-GENERADO por scripts/tools/extract-weapon-metas.py -- NO EDITAR A MANO',
    '-- data/ sale de los .rpf de GTA V ' + build + ' y es SOLO referencia: no se declara nada de',
    '-- ahi. base/ es la version de update.rpf (o de common.rpf si solo esta ahi) y',
    '-- dlc/<pack>/ la que gana en ese DLC. El script regenera data/ entera en cada pasada.',
    '--',
    '-- custom/ es lo que se aplica de verdad y ese script no la toca: la escribe',
    '-- scripts/tools/build-weapon-fx.py, que copia el .meta de data/ y le mete el bloque <Fx> del',
    '-- pack de armas. Para cambiar algo se edita el script y se vuelve a lanzar.',
    '--',
    '-- Todas las armas (tanto las 18 base en custom/weapons.meta como las 41 de DLC en sus archivos',
    '-- individuales) se cargan EXCLUSIVAMENTE mediante WEAPONINFO_FILE_PATCH.',
    '--',
    '-- No se usa WEAPONINFO_FILE: en FiveM, WEAPONINFO_FILE sobre armas existentes añade una copia',
    '-- duplicada al pool de CWeaponInfo en vez de pisar la original, lo que rompía los efectos y',
    '-- hacía que SetWeaponRecoilShakeAmplitude modificara una instancia inactiva en memoria.',
    '-- Con WEAPONINFO_FILE_PATCH, el motor parchea in-place la definición activa de cada arma.',
    '--',
    '-- Y ojo al depurar "no se ve el efecto": si el arma lleva supresor manda el componente, no el',
    '-- arma. CWeaponComponentSuppressorInfo trae su propio <FlashFx> (muz_pistol_silencer) y mueve',
    '-- el efecto al hueso Gun_SuMuzzle, que los modelos de M9A3, MP5 y Glock18C no tienen, asi que',
    '-- con supresor puesto no sale ni fogonazo ni humo diga lo que diga el .meta.',
    '--',
    '-- Los .meta que no son de armas sueltas necesitan otro tipo de data_file:',
    '--   weaponanimations.meta       -> WEAPON_ANIMATIONS_FILE',
    '--   weaponcomponents.meta       -> WEAPONCOMPONENTSINFO_FILE',
    '--   weaponarchetypes.meta       -> WEAPON_METADATA_FILE',
    '',
    'files {',
    "    'custom/weapon*.meta',",
    '}',
    '',
    "data_file 'WEAPONINFO_FILE_PATCH' 'custom/weapon*.meta'",
]
# LF y no CRLF: es como esta el fxmanifest en el repo, asi regenerarlo no ensucia el diff.
with open(os.path.join(OUT, 'fxmanifest.lua'), 'w', encoding='utf-8', newline='\n') as f:
    f.write('\n'.join(lua) + '\n')

print('%d .meta de referencia en %s  (%d en custom/, que es lo que se aplica)'
      % (len(best), data_dir, n_custom))

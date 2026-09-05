#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
    Regenera resources/[weapons]/weapon_meta/custom/ entera: los .meta de armas del
    server con el bloque <Fx> del pack de armas (weapon.rar), y verifica que lo unico
    que cambia respecto al dump vanilla de data/ es ese bloque.

    Es el companyero de extract-weapon-metas.ps1: ese saca data/ de los .rpf del juego,
    esto escribe custom/ a partir de data/ + el pack. Va en Python y no en Bun porque el
    trabajo es texto sobre 22k lineas de XML mal indentado (hay tabs y espacios mezclados
    en el vanilla) y aqui se conserva byte a byte todo lo que no se toca.

    Uso:  python scripts/tools/build-weapon-fx.py
          python scripts/tools/build-weapon-fx.py --pack 'C:/.../weapon/client' --probe

    --probe pone en cada arma un <TimeBetweenShots> acabado en 777 para poder medir con
    /fxprobeall que armas aplica de verdad el motor (ver el comentario del fxmanifest de
    weapon_meta: las armas base entran por WEAPONINFO_FILE y eso duplica la entrada, asi
    que hay armas que se quedan con los valores vanilla).
"""
import argparse, io, os, re, sys, textwrap
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
RES  = os.path.join(REPO, 'resources')

ap = argparse.ArgumentParser()
ap.add_argument('--pack', default='C:/Users/KernKode/Desktop/weapon/client',
                help='carpeta client/ del pack de armas (los .meta de donde sale el <Fx>)')
ap.add_argument('--out',  default=None, help='destino (por defecto weapon_meta/custom)')
ap.add_argument('--probe', action='store_true', help='marcar TimeBetweenShots con 777')
args = ap.parse_args()

PACKD = args.pack.replace('\\', '/')
META  = os.path.join(RES, '[weapons]', 'weapon_meta')
DATA  = os.path.join(META, 'data').replace('\\', '/')
CUST  = (args.out or os.path.join(META, 'custom')).replace('\\', '/')
BASE  = DATA + '/base/weapons.meta'
CONF  = os.path.join(RES, '[gameplay]', 'inventory', 'shared', 'config.lua')

read  = lambda p: io.open(p, encoding='utf-8', errors='replace').read()
write = lambda p, s: io.open(p, 'w', encoding='utf-8', newline='\r\n').write(s)

# el .meta de la Glock traia este tag mal escrito; en vanilla es FlashFxFPAlt
RENAME = {'FlashFxAltFP': 'FlashFxFPAlt'}
# tag -> tras cual insertarlo cuando el vanilla no lo trae
ANCHOR = {'FlashFxFP': 'FlashFxAlt', 'FlashFxFPAlt': 'FlashFxFP', 'MuzzleSmokeFxFP': 'MuzzleSmokeFx'}


def item_end(t, s):
    """indice tras el </Item> que cierra el <Item> abierto en s (hay <Item> anidados)"""
    depth, j = 0, s
    while True:
        m = re.compile(r'<Item\b[^>]*?(/?)>|</Item>').search(t, j)
        if m.group(0).startswith('</'): depth -= 1
        elif m.group(1) != '/':        depth += 1
        j = m.end()
        if depth == 0: return j


def scan(path):
    """(texto, [(arma, ini_item, ini_siguiente, ini_fx, fin_fx)]) de un .meta"""
    t, out = read(path), []
    st = [m.start() for m in re.finditer(r'<Item type="CWeaponInfo">', t)]
    for i, s in enumerate(st):
        e = st[i + 1] if i + 1 < len(st) else len(t)
        nm = re.search(r'<Name>(WEAPON_\w+)</Name>', t[s:e])
        a, b = t.find('<Fx>', s), t.find('</Fx>', s)
        if nm and 0 <= a < e and 0 <= b < e: out.append((nm.group(1), s, e, a, b))
    return t, out


def fx_map(path, weapon):
    """tag -> linea del <Fx> de esa arma"""
    t, its = scan(path)
    for nm, s, e, a, b in its:
        if nm != weapon: continue
        d = {}
        for l in t[a:b].split('\n')[1:]:
            l = l.strip()
            if l.startswith('<'):
                k = re.match(r'<(\w+)', l).group(1)
                d[RENAME.get(k, k)] = l
        return d
    raise KeyError('%s no esta en %s' % (weapon, path))


val = lambda l: re.search(r'value="([^"]+)"', l).group(1)
txt = lambda l: (re.match(r'<\w+>(.*?)</\w+>', l).group(1).strip()
                 if re.match(r'<\w+>(.*?)</\w+>', l) else '')
f6  = lambda v: '%.6f' % float(v)


def plan(p):
    """lo que se copia del pack: fogonazo, humo, trazadoras y el alcance de la luz.

    Se quedan vanilla el ShellFx, el PedDamageHash, el MuzzleOverrideOffset y el
    GroundDisturb: el pack pone valores de fusil en todas las armas y eso ya no es el
    fogonazo. Los *FP se rellenan con el efecto de tercera persona porque el pack los
    borra y en primera te quedarias sin nada. Las dos TracerFxChance van a 0 ademas del
    <TracerFx> vacio: solo vaciar el nombre no siempre quita la trazadora.
    """
    flash, alt, smoke = txt(p['FlashFx']), txt(p['FlashFxAlt']), txt(p['MuzzleSmokeFx'])
    tag = lambda n, v: '<%s>%s</%s>' % (n, v, n) if v else '<%s />' % n
    rng = p['FlashFxLightRangeMinMax']
    return {
        'FlashFx':                 tag('FlashFx', flash),
        'FlashFxAlt':              tag('FlashFxAlt', alt),
        'FlashFxFP':               tag('FlashFxFP', flash),
        'FlashFxFPAlt':            tag('FlashFxFPAlt', alt),
        'MuzzleSmokeFx':           tag('MuzzleSmokeFx', smoke),
        'MuzzleSmokeFxFP':         tag('MuzzleSmokeFxFP', smoke),
        'MuzzleSmokeFxMinLevel':   '<MuzzleSmokeFxMinLevel value="%s" />'   % f6(val(p['MuzzleSmokeFxMinLevel'])),
        'MuzzleSmokeFxIncPerShot': '<MuzzleSmokeFxIncPerShot value="%s" />' % f6(val(p['MuzzleSmokeFxIncPerShot'])),
        'MuzzleSmokeFxDecPerSec':  '<MuzzleSmokeFxDecPerSec value="%s" />'  % f6(val(p['MuzzleSmokeFxDecPerSec'])),
        'TracerFx':                '<TracerFx />',
        'TracerFxChanceSP':        '<TracerFxChanceSP value="0.000000" />',
        'TracerFxChanceMP':        '<TracerFxChanceMP value="0.000000" />',
        'FlashFxAltChance':        '<FlashFxAltChance value="%s" />' % f6(val(p['FlashFxAltChance'])),
        'FlashFxScale':            '<FlashFxScale value="%s" />'     % f6(val(p['FlashFxScale'])),
        'FlashFxLightRangeMinMax': '<FlashFxLightRangeMinMax x="%s" y="%s" />' % (
            f6(re.search(r'x="([^"]+)"', rng).group(1)), f6(re.search(r'y="([^"]+)"', rng).group(1))),
    }


def patch_fx(block, pack_fx, probe=False):
    """devuelve el bloque del arma con el <Fx> cambiado (y la sonda, si toca)"""
    p, done, out, inside = plan(pack_fx), set(), [], False

    def extras(tag, indent):
        for ex, an in ANCHOR.items():
            if an == tag and ex in p and ex not in done and ('<%s' % ex) not in block:
                out.append(indent + p[ex]); done.add(ex); extras(ex, indent)

    for line in block.split('\n'):
        s, indent = line.strip(), line[:len(line) - len(line.lstrip())]
        if s.startswith('<Fx>'):  inside = True
        if s.startswith('</Fx>'): inside = False
        if probe and s.startswith('<TimeBetweenShots '):
            out.append(indent + '<TimeBetweenShots value="%.6f" />' % (round(float(val(s)), 3) + 0.000777))
            continue
        if inside and s.startswith('<'):
            raw = re.match(r'<(\w+)', s).group(1)
            tag = RENAME.get(raw, raw)
            if tag in p:
                out.append(indent + p[tag]); done.add(tag); extras(tag, indent); continue
        out.append(line)
    if set(p) - done: raise SystemExit('tags sin sitio: %s' % sorted(set(p) - done))
    return '\n'.join(out)


def patch_stats(block, fields):
    """devuelve el bloque del arma con los valores de STATS puestos.

    Solo se toca lo que hay DENTRO de las comillas: el resto de la linea (sangrado, espacios,
    fin de linea) se conserva byte a byte, igual que hace el resto del script. Si un tag de
    STATS no existe en el arma se aborta: seria un override que no hace nada.
    """
    for tag, value in sorted(fields.items()):
        block, n = re.subn(r'(<%s value=")[^"]*(")' % tag, r'\g<1>%s\g<2>' % value, block, count=1)
        if n != 1: raise SystemExit('STATS: <%s> no esta en el arma' % tag)
    return block


CLIP_ITEM = re.compile(r'<Item>\s*<Name>(COMPONENT_\w+)</Name>\s*<Default value="[^"]*" />\s*</Item>')


def patch_default_clip(block, component):
    """devuelve el bloque del arma con `component` como cargador de serie.

    De los <Components> del arma se pone <Default value="true"/> en ese CLIP_* y "false" en
    los demas; el resto de componentes (supresores, miras) no se toca. Igual que patch_stats,
    solo cambia lo de dentro de las comillas.
    """
    vistos = []

    def uno(m):
        nombre = m.group(1)
        vistos.append(nombre)
        if '_CLIP_' not in nombre: return m.group(0)
        quiero = 'true' if nombre == component else 'false'
        return re.sub(r'(<Default value=")[^"]*(")', r'\g<1>%s\g<2>' % quiero, m.group(0))

    block = CLIP_ITEM.sub(uno, block)
    if component not in vistos: raise SystemExit('DEFCLIP: %s no esta en el arma' % component)
    return block


def con_defclip(lines, component):
    """las lineas del vanilla con el mismo cambio, para poder comparar (ver verificacion)"""
    out, cur = [], None
    for l in lines:
        m = re.match(r'<Name>(COMPONENT_\w+)</Name>$', l)
        if m: cur = m.group(1)
        if cur and '_CLIP_' in cur and l.startswith('<Default value='):
            l = '<Default value="%s" />' % ('true' if cur == component else 'false')
        out.append(l)
    return out



def comment(paras):
    body = '\n\n'.join(textwrap.fill(' '.join(x.split()), width=96,
                                     initial_indent='     ', subsequent_indent='     ')
                       for x in paras if x and x.strip())
    if '--' in body: raise SystemExit('un comentario XML no puede llevar doble guion: %r' % body)
    return '<!--' + body[4:] + ' -->'


# ---------------------------------------------------------------- de donde sale cada <Fx>
SRC = {  # arma -> arma del pack cuyo <Fx> se le copia
 'WEAPON_APPISTOL':          'WEAPON_MACHINEPISTOL',   # es la Glock 18C, pedido a mano
 'WEAPON_HEAVYSNIPER_MK2':   'WEAPON_HEAVYSNIPER',     # el pack no toco estos dos mk2
 'WEAPON_MARKSMANRIFLE_MK2': 'WEAPON_MARKSMANRIFLE',
 # armas posteriores al pack (2019): se les pone el de la mas parecida
 'WEAPON_BATTLERIFLE':    'WEAPON_CARBINERIFLE',
 'WEAPON_MILITARYRIFLE':  'WEAPON_CARBINERIFLE',
 'WEAPON_TACTICALRIFLE':  'WEAPON_CARBINERIFLE',
 'WEAPON_HEAVYRIFLE':     'WEAPON_ASSAULTRIFLE',
 'WEAPON_COMBATSHOTGUN':  'WEAPON_ASSAULTSHOTGUN',
 'WEAPON_PRECISIONRIFLE': 'WEAPON_SNIPERRIFLE',
 'WEAPON_CERAMICPISTOL':  'WEAPON_PISTOL',
 'WEAPON_GADGETPISTOL':   'WEAPON_PISTOL',
 'WEAPON_PISTOLXM3':      'WEAPON_PISTOL',
 'WEAPON_NAVYREVOLVER':   'WEAPON_REVOLVER',
 'WEAPON_TECPISTOL':      'WEAPON_MACHINEPISTOL',
}
NUEVAS = ['WEAPON_BATTLERIFLE', 'WEAPON_MILITARYRIFLE', 'WEAPON_TACTICALRIFLE', 'WEAPON_HEAVYRIFLE',
          'WEAPON_COMBATSHOTGUN', 'WEAPON_PRECISIONRIFLE', 'WEAPON_CERAMICPISTOL',
          'WEAPON_GADGETPISTOL', 'WEAPON_PISTOLXM3', 'WEAPON_NAVYREVOLVER', 'WEAPON_TECPISTOL']
AUDIO = {'WEAPON_APPISTOL': 'AUDIO_ITEM_PISTOL'}   # la Glock necesita el audio que si reemplaza weapon_sounds

# Retoques de BALANCE, arma por arma: lo unico que este script cambia del vanilla aparte del
# <Fx> y del <Audio> de arriba. Van aqui y no a mano en custom/ porque custom/ se borra y se
# reescribe entero en cada pasada.
#
# El retroceso del jugador en GTA sale de estos tres campos, no del <RecoilShakeAmplitude>
# (ese es solo el temblor de camara, y encima [gameplay]/inventory lo pisa en caliente por
# arma con `recoil` de su config):
#   RecoilAccuracyMax    cuanto se abre la punteria disparando seguido (82 de las 91 armas del
#                        vanilla llevan 1.0; la microsmg venia con 0.5, de las mas blandas)
#   RecoilErrorTime      segundos hasta llegar a ese maximo (74 de 91 llevan 0.0, o sea al
#                        instante; con el 1.5 que traia, la rafaga tardaba en abrirse)
#   IkRecoilDisplacement el golpe VISIBLE del arma en las manos. En el vanilla solo lo llevan
#                        tres pistolas: 0.01 la PISTOL y la PISTOL50, 0.005 la COMBATPISTOL
STATS = {}

# Cargador de serie, arma por arma. El <ClipSize> del ARMA solo manda cuando no lleva ningun
# componente de cargador puesto, y el CLIP_01 va de serie en todas las armas de fuego, asi que
# la capacidad real de la recamara es la del COMPONENTE. Y esos <ClipSize> viven en
# weaponcomponents.meta, que este server no carga (haria falta un WEAPONCOMPONENTSINFO_FILE, y
# el blob lleva refs a su propio <Data>: RELOAD_DEFAULT y compania). Para subir la recamara sin
# eso se pone de serie otro componente de cargador que YA exista con mas capacidad.
DEFCLIP = {
    # La P90 ([weapons]/P90) lleva cargador de 50 y el CLIP_01 del ASSAULTSMG es de 30: con el
    # de serie, de las 50 balas del item solo 30 entraban en la recamara y las otras 20 caian
    # en la reserva. El CLIP_02 es de 60, o sea que las 50 entran de una sola vez.
    #
    # Su modelo es el W_SB_ASSAULTSMG_Mag2, que el recurso de la P90 envia VACIO (el cargador
    # de la P90 va modelado en el cuerpo), asi que no se ve ningun cargador pegado. Y el item
    # `at_clip_extended_rifle` del inventario tiene vetada esta arma con `noAttach`, asi que
    # nadie sube de 50: las 60 de la recamara son solo el techo, el tope lo pone el item.
    #
    # Efecto de paso: el CLIP_02 lleva bShownOnWheel="true", asi que la rueda de armas ensenya
    # el cargador ampliado como puesto.
    'WEAPON_ASSAULTSMG': 'COMPONENT_ASSAULTSMG_CLIP_02',
}

# ---------------------------------------------------------------- indices
ours = sorted(set(re.findall(r'weapon = "(WEAPON_[A-Z0-9_]+)"', read(CONF))))
pack = {}
for fn in sorted(os.listdir(PACKD)):
    if fn.endswith('.meta') and fn != 'weaponanimations.meta':
        for nm, s, e, a, b in scan(PACKD + '/' + fn)[1]: pack.setdefault(nm, PACKD + '/' + fn)
van = {nm: (BASE, 'base/weapons.meta') for nm, s, e, a, b in scan(BASE)[1]}
for root, _, fs in os.walk(DATA + '/dlc'):
    for fn in sorted(fs):
        if not fn.endswith('.meta'): continue
        p = os.path.join(root, fn).replace(os.sep, '/')
        for nm, s, e, a, b in scan(p)[1]: van[nm] = (p, p[len(DATA) + 1:])

FXKEYS = ['FlashFx', 'FlashFxAlt', 'MuzzleSmokeFx', 'MuzzleSmokeFxMinLevel', 'MuzzleSmokeFxIncPerShot',
          'MuzzleSmokeFxDecPerSec', 'TracerFx', 'FlashFxAltChance', 'FlashFxScale', 'FlashFxLightRangeMinMax']


def norm(l):
    if l is None: return None
    if 'value=' in l: return '%.4f' % float(val(l))
    if ' x=' in l:    return ','.join('%.4f' % float(re.search(a + r'="([^"]+)"', l).group(1)) for a in 'xy')
    return txt(l)


# armas nuestras a las que el pack les cambia algo (mas las posteriores al pack)
todo = []
for w in ours:
    src = SRC.get(w, w)
    if src not in pack or w not in van: continue
    pfx, vfx = fx_map(pack[src], src), fx_map(van[w][0], w)
    if w in NUEVAS or any(norm(pfx.get(k)) is not None and norm(pfx.get(k)) != norm(vfx.get(k)) for k in FXKEYS):
        todo.append(w)
base_ws = [w for w in todo if van[w][1] == 'base/weapons.meta']
print('armas: %d (%d base, %d de dlc)' % (len(todo), len(base_ws), len(todo) - len(base_ws)))

# STATS y DEFCLIP solo se aplican a las armas que este script escribe. Si se pone un retoque en
# un arma que no entra en `todo` (porque el pack no le cambia el <Fx>) no pasaria nada en
# absoluto, asi que se aborta en vez de dejarlo pasar en silencio.
huerfanas = sorted((set(STATS) | set(DEFCLIP)) - set(todo))
if huerfanas: raise SystemExit('STATS/DEFCLIP de armas que este script no escribe: %s' % huerfanas)

P_FX  = (u'con los efectos del %(src)s del pack weapon.rar en el bloque <Fx>: fogonazo muz_stungun, '
         u'humo de minigun, sin trazadoras (el <TracerFx> vacio del pack y, por si eso solo no basta, '
         u'las dos <TracerFxChance> a 0) y el FlashFxScale del pack (el fogonazo del stungun es grande '
         u'y a escala vanilla se ve inflado).')
P_VAN = (u'Los campos *FP van con el mismo efecto que en tercera persona, que el pack los borra y en '
         u'primera te quedas sin nada. Se quedan vanilla el ShellFx, el PedDamageHash, el '
         u'MuzzleOverrideOffset y el GroundDisturb: el pack pone valores de fusil en todo y eso ya no '
         u'es el fogonazo.')
P_SLOT = (u'Los <SlotNavigateOrder>/<SlotBestOrder> van vacios a proposito: el orden del slot lo sigue '
          u'poniendo el weapons.meta base.')
P_GEN  = u'AUTO-GENERADO por scripts/tools/build-weapon-fx.py: se edita ese script, no este archivo.'
P_NEW  = (u'%s no esta en el pack (es posterior a 2019), asi que su <Fx> sale del %s por parecido de '
          u'calibre y de tamanyo de fogonazo.')
P_MK2  = (u'El weapons_%s_mk2.meta del pack es vanilla sin tocar (fogonazo muz_alternate_star y sin '
          u'humo), asi que el mk2 coge el <Fx> de su hermana base.')
P_AP   = (u'El appistol es la Glock 18C de [weapons]/Glock18C: su <Fx> sale del MACHINEPISTOL del pack, '
          u'pedido a mano, y su <Audio> pasa de AUDIO_ITEM_APPISTOL a AUDIO_ITEM_PISTOL, que es el '
          u'unico de los dos que reemplaza [gameplay]/weapon_sounds.')
P_STATS = (u'El %s lleva ademas los retoques de balance de STATS en el script: RecoilAccuracyMax, '
           u'RecoilErrorTime e IkRecoilDisplacement, que es de donde sale el retroceso que nota el '
           u'jugador (el RecoilShakeAmplitude es solo temblor de camara, y encima lo pisa en caliente '
           u'[gameplay]/inventory con el `recoil` de su config).')
P_CLIP  = (u'Al %s se le cambia el cargador de serie a %s (el DEFCLIP del script): el <ClipSize> del '
           u'arma solo cuenta si no lleva componente de cargador, y el de serie es de 30 cuando esa '
           u'arma necesita mas. El <ClipSize> de un componente vive en weaponcomponents.meta, que no '
           u'se carga aqui, asi que en vez de parchearlo se pone de serie un cargador que ya existe '
           u'con la capacidad que hace falta.')

# ---------------------------------------------------------------- generacion
if not os.path.isdir(CUST): os.makedirs(CUST)
for fn in os.listdir(CUST):
    if fn.endswith('.meta'): os.remove(CUST + '/' + fn)

hechos = []

# armas base -> un unico weapons.meta que parchea las armas base via WEAPONINFO_FILE_PATCH
t, its = scan(BASE)
for nm, s, e, a, b in sorted(its, key=lambda x: -x[1]):
    if nm not in base_ws: continue
    end = item_end(t, s)
    item = patch_fx(t[s:end], fx_map(pack[SRC.get(nm, nm)], SRC.get(nm, nm)), args.probe)
    if nm in AUDIO:
        item = re.sub(r'<Audio>\w+</Audio>', '<Audio>%s</Audio>' % AUDIO[nm], item, count=1)
    if nm in STATS:
        item = patch_stats(item, STATS[nm])
    if nm in DEFCLIP:
        item = patch_default_clip(item, DEFCLIP[nm])
    t = t[:s] + item + t[end:]

extra = [P_AP] if any(w in AUDIO for w in base_ws) else []
extra += [P_STATS % w[7:] for w in base_ws if w in STATS]
extra += [P_CLIP % (w[7:], DEFCLIP[w][10:]) for w in base_ws if w in DEFCLIP]
srcs = ', '.join(sorted(set(SRC.get(w, w)[7:] for w in base_ws)))
paras = [P_GEN,
         u'Copia del weapons.meta base vanilla de GTA V 1.0.3889.0 (data/base/weapons.meta) '
         u'con los efectos del pack weapon.rar en el bloque <Fx> de las 18 armas base '
         u'(%s).' % srcs,
         P_VAN] + extra
first = t.index('\n') + 1
write(CUST + '/weapons.meta', t[:first] + '\n' + comment(paras) + '\n' + t[first:].lstrip('\r\n'))
hechos.append(('weapons.meta', base_ws))

porfile = {}
for w in todo:
    if w not in base_ws: porfile.setdefault(van[w][0], []).append(w)
for path, ws in sorted(porfile.items()):            # arma de DLC -> copia de su .meta
    t, its = scan(path)
    for nm, s, e, a, b in sorted(its, key=lambda x: -x[1]):
        if nm not in ws: continue
        end = item_end(t, s)
        item = patch_fx(t[s:end], fx_map(pack[SRC.get(nm, nm)], SRC.get(nm, nm)), args.probe)
        if nm in STATS:
            item = patch_stats(item, STATS[nm])
        if nm in DEFCLIP:
            item = patch_default_clip(item, DEFCLIP[nm])
        t = t[:s] + item + t[end:]
    extra = []
    for w in ws:
        if w in NUEVAS:                 extra.append(P_NEW % (w[7:], SRC[w][7:]))
        if w.endswith('_MK2') and w in SRC: extra.append(P_MK2 % w[7:-4].lower())
        if w in STATS:                  extra.append(P_STATS % w[7:])
        if w in DEFCLIP:                extra.append(P_CLIP % (w[7:], DEFCLIP[w][10:]))
    srcs = ', '.join(sorted(set(SRC.get(w, w)[7:] for w in ws)))
    paras = [P_GEN, u'Copia del %s vanilla de GTA V 1.0.3889.0 (data/%s) ' % (
             os.path.basename(path), van[ws[0]][1]) + P_FX % {'src': srcs}, P_VAN] + extra
    first = t.index('\n') + 1
    fn = os.path.basename(path)
    write(CUST + '/' + fn, t[:first] + '\n' + comment(paras) + '\n' + t[first:].lstrip('\r\n'))
    hechos.append((fn, ws))
print('archivos escritos:', len(hechos), '| sonda:', 'si' if args.probe else 'no')


# ---------------------------------------------------------------- verificacion
def sin_fx(path, weapon):
    """el bloque del arma sin su <Fx>, linea a linea, para comparar contra el vanilla"""
    t, its = scan(path)
    s = [i for i in its if i[0] == weapon][0][1]
    blk = t[s:item_end(t, s)]
    i, f = blk.index('<Fx>'), blk.index('</Fx>')
    return [l.strip() for l in (blk[:i] + blk[f:]).split('\n') if l.strip()]


fallos, n = 0, 0
for fn, ws in hechos:
    p = CUST + '/' + fn
    ET.parse(p)                                             # 1) XML valido
    for w, s, e, a, b in scan(p)[1]:
        if w not in todo:                                   # arma de acompanyamiento: vanilla clavado
            if sin_fx(van[w][0], w) != sin_fx(p, w) or fx_map(van[w][0], w) != fx_map(p, w):
                print('  ARMA DE PASO TOCADA', fn, w); fallos += 1
            continue
        n += 1
        want, got = fx_map(pack[SRC.get(w, w)], SRC.get(w, w)), fx_map(p, w)
        for k in FXKEYS:                                    # 2) el <Fx> es el del pack
            if norm(want.get(k)) is not None and norm(got.get(k)) != norm(want.get(k)):
                print('  FX MAL', fn, w, k, norm(got.get(k)), '!=', norm(want.get(k))); fallos += 1
        for k, base in (('FlashFxFP', 'FlashFx'), ('FlashFxFPAlt', 'FlashFxAlt'),
                        ('MuzzleSmokeFxFP', 'MuzzleSmokeFx')):
            if txt(got.get(k, '<x></x>')) != txt(want[base]):
                print('  FP MAL', fn, w, k); fallos += 1
        for k in ('TracerFxChanceSP', 'TracerFxChanceMP'):
            if norm(got.get(k)) != '0.0000': print('  TRAZADORA', fn, w, k); fallos += 1
        a1, b1 = sin_fx(van[w][0], w), sin_fx(p, w)         # 3) lo de fuera del <Fx>, vanilla
        if w in AUDIO:
            a1 = [re.sub(r'<Audio>\w+</Audio>', '<Audio>%s</Audio>' % AUDIO[w], l) for l in a1]
        if w in STATS:
            # Al vanilla se le aplican los MISMOS retoques antes de comparar: asi este chequeo
            # sigue cazando cualquier OTRA diferencia con el dump, que es para lo que esta.
            def con_stats(l, fields=STATS[w]):
                for tag, value in fields.items():
                    if ('<%s value=' % tag) in l: return patch_stats(l, {tag: value})
                return l
            a1 = [con_stats(l) for l in a1]
        if w in DEFCLIP:
            a1 = con_defclip(a1, DEFCLIP[w])
        if args.probe:
            a1 = [l for l in a1 if not l.startswith('<TimeBetweenShots ')]
            b1 = [l for l in b1 if not l.startswith('<TimeBetweenShots ')]
        if a1 != b1: print('  FUERA DEL FX MAL', fn, w); fallos += 1

print('armas verificadas: %d | fallos: %d' % (n, fallos))
sys.exit(1 if fallos else 0)

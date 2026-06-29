/**
 * Lua test harness for KeCore. Runs the real framework Lua inside a Lua 5.4 VM
 * (wasmoon) with the FiveM/CitizenFX natives mocked, so the events fixes and the
 * generated performance/ modules can be exercised behaviourally — not just
 * syntax-checked — without a running FXServer.
 *
 *   bun scripts/test/run-lua-tests.ts
 */
import path from 'path';
import fs from 'fs/promises';
import { LuaFactory } from 'wasmoon';

const KECORE = path.resolve('resources', '[framework]', 'kecore');
const read = (rel: string) => fs.readFile(path.join(KECORE, rel), 'utf8');

let passed = 0;
let failed = 0;
const fail = (msg: string) => { failed++; console.log(`  \x1b[31m✗ FAIL\x1b[0m ${msg}`); };
const ok = (msg: string) => { passed++; console.log(`  \x1b[32m✓\x1b[0m ${msg}`); };
function assert(cond: unknown, msg: string) { cond ? ok(msg) : fail(msg); }

// CfxLua compile-time hash literals `like_this` aren't standard Lua 5.4.
const stripCfxHashes = (src: string) => src.replace(/`[^`]*`/g, '0');

// ─────────────────────────────────────────────────────────────────────────────
// 1. SYNTAX: every generated performance file + the edited internal sources load.
// ─────────────────────────────────────────────────────────────────────────────
async function testSyntax() {
    console.log('\n\x1b[1m[1] Syntax — load every generated performance/ file + edited internal\x1b[0m');
    const lua = await new LuaFactory().createEngine();

    const perfDir = path.join(KECORE, 'performance');
    const files: string[] = [];
    const walk = async (dir: string) => {
        for (const e of await fs.readdir(dir, { withFileTypes: true })) {
            const p = path.join(dir, e.name);
            if (e.isDirectory()) await walk(p);
            else if (e.name.endsWith('.lua')) files.push(p);
        }
    };
    await walk(perfDir);
    files.push(path.join(KECORE, 'internal/shared/events/manager.lua'));
    files.push(path.join(KECORE, 'internal/shared/core.lua'));

    for (const f of files.sort()) {
        let src = await fs.readFile(f, 'utf8');
        if (f.endsWith('natives.lua')) src = stripCfxHashes(src);
        lua.global.set('__SRC', src);
        const err = await lua.doString('local fn, e = load(__SRC, "chunk"); return e');
        assert(err == null, `loads: ${path.relative(KECORE, f).replace(/\\/g, '/')}${err ? `  → ${err}` : ''}`);
    }
    lua.global.close();
}

// ─────────────────────────────────────────────────────────────────────────────
// Build a Lua VM with FiveM natives mocked + kec loaded (core.lua + manager.lua).
// ─────────────────────────────────────────────────────────────────────────────
async function makeKecVM(isServer: boolean, managerSrc?: string) {
    const lua = await new LuaFactory().createEngine();
    const g = lua.global;

    // Event registry shared with JS so we can fire events and inspect handlers.
    type H = { name: string; fn: any; token: number; removed: boolean };
    const handlers: H[] = [];
    let token = 0;
    let invokingResource = 'consumerRes';

    const register = (name: string, fn: any) => { const t = ++token; handlers.push({ name, fn, token: t, removed: false }); return t; };
    g.set('RegisterNetEvent', register);
    g.set('AddEventHandler', register);
    g.set('RemoveEventHandler', (t: number) => { const h = handlers.find(x => x.token === t); if (h) h.removed = true; });
    g.set('IsDuplicityVersion', () => isServer);
    g.set('GetHashKey', (s: string) => s.length);
    g.set('GetInvokingResource', () => invokingResource);
    g.set('Wait', () => {});
    g.set('exports', (_name: string, _fn: any) => {}); // core.lua: exports('get', ...)

    await lua.doString(await read('internal/shared/core.lua'));
    await lua.doString(managerSrc ?? await read('internal/shared/events/manager.lua'));

    // Fire an event by name (sets the implicit FiveM `source` global first).
    const fire = async (name: string, source: string, ...args: any[]) => {
        g.set('source', source);
        for (const h of handlers.filter(x => x.name === name && !x.removed)) {
            await h.fn(...args);
        }
    };

    return {
        lua,
        fire,
        handlers,
        tokensFor: (name: string) => handlers.filter(h => h.name === name).map(h => h.token),
        removed: (t: number) => !!handlers.find(h => h.token === t)?.removed,
        setInvokingResource: (r: string) => { invokingResource = r; },
        run: (code: string) => lua.doString(code),
        close: () => g.close(),
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Bug #3.1 — handler leak: all handlers of a resource removed on stop.
// ─────────────────────────────────────────────────────────────────────────────
async function testHandlerLeak() {
    console.log('\n\x1b[1m[2] Bug fix — handler cache is per-resource array (no leak)\x1b[0m');
    const vm = await makeKecVM(true);
    vm.setInvokingResource('resA');
    await vm.run('kec:on("evt1", function() end)');
    await vm.run('kec:on("evt2", function() end)');
    await vm.run('kec:on("evt3", function() end)');

    const evtTokens = [...vm.tokensFor('evt1'), ...vm.tokensFor('evt2'), ...vm.tokensFor('evt3')];
    assert(evtTokens.length === 3, `registered 3 event handlers (got ${evtTokens.length})`);
    assert(evtTokens.every(t => !vm.removed(t)), 'none removed before resource stop');

    await vm.fire('onResourceStop', '', 'resA');

    assert(evtTokens.every(t => vm.removed(t)), `ALL 3 handlers removed on resource stop (removed: ${evtTokens.filter(t => vm.removed(t)).length}/3)`);
    vm.close();
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Bug #3.2 — onLocal error path uses kec.debugEvents, doesn't crash on `shared`.
// ─────────────────────────────────────────────────────────────────────────────
async function testDebugFlag() {
    console.log('\n\x1b[1m[3] Bug fix — onLocal error path (no undefined `shared` crash)\x1b[0m');
    const vm = await makeKecVM(false);

    // `shared` must be nil — the old code (shared.debugMode) would crash here.
    const sharedIsNil = await vm.run('return shared == nil');
    assert(sharedIsNil === true, '`shared` global is undefined (old code would index nil)');

    await vm.run('kec.debugEvents = true');
    await vm.run('kec:onLocal("localEvt", function() error("boom") end)');

    let threw = false;
    try { await vm.fire('localEvt', ''); } catch { threw = true; }
    assert(!threw, 'firing a throwing local callback does not crash the handler');
    vm.close();
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Bug #3.3 — callFunc returns its own (ok, err): a failing callback is detected
//    via the local result, independent of any outer/registration state.
// ─────────────────────────────────────────────────────────────────────────────
async function testCallbackErrorIsolation() {
    console.log('\n\x1b[1m[4] Bug fix — callback error captured via local (ok, err)\x1b[0m');
    const vm = await makeKecVM(true);
    // Capture debug output from Lua print.
    const lines: string[] = [];
    vm.lua.global.set('print', (...a: any[]) => lines.push(a.join('\t')));
    await vm.run('kec.debugEvents = true');

    await vm.run('kec:on("good", function() return true end)');
    await vm.run('kec:on("bad", function() error("kapow") end)');

    await vm.fire('good', 'src1', 'x');     // success → no error line
    const afterGood = lines.length;
    await vm.fire('bad', 'src2', 'y');      // failure → error line printed

    assert(afterGood === 0, 'successful callback prints no error');
    assert(lines.some(l => l.includes('kapow')), 'failing callback prints its OWN error (kapow)');
    vm.close();
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Bug #3.4 — on_resource_start fires for the original caller, not framework.
// ─────────────────────────────────────────────────────────────────────────────
async function testResourceStartContext() {
    console.log('\n\x1b[1m[5] Bug fix — on_resource_start uses the captured caller\x1b[0m');
    const vm = await makeKecVM(false);
    vm.lua.global.set('print', () => {});

    vm.setInvokingResource('myResource');         // caller at REGISTRATION time
    await vm.run('FIRED = 0');
    await vm.run('kec:on_resource_start(function() FIRED = FIRED + 1 end)');

    vm.setInvokingResource('kecore');              // framework context at EVENT time

    await vm.fire('onResourceStart', '', 'otherRes');
    assert(await vm.run('return FIRED') === 0, 'does NOT fire for a different resource');

    await vm.fire('onResourceStart', '', 'myResource');
    assert(await vm.run('return FIRED') === 1, 'fires exactly once for the original caller');
    vm.close();
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Generated performance modules work functionally (transform produced valid code).
// ─────────────────────────────────────────────────────────────────────────────
async function testPerformanceModules() {
    console.log('\n\x1b[1m[6] Functional — generated performance/ modules behave correctly\x1b[0m');
    const lua = await new LuaFactory().createEngine();
    lua.global.set('print', () => {});
    lua.global.set('GetGameTimer', () => 0); // lru_cache TTL/purge uses this

    // base64 round-trip
    lua.global.set('__B64', await read('performance/shared/base64.lua'));
    const b64 = await lua.doString(`
        local base64 = load(__B64)()
        local enc = base64:encode("Hello, KeCore! 123")
        local dec = base64:decode(enc)
        return dec
    `);
    assert(b64 === 'Hello, KeCore! 123', `base64 encode→decode round-trips (got "${b64}")`);

    // lru_cache eviction (API: :put / :get; max_size 2 → oldest "a" evicted on 3rd put)
    lua.global.set('__LRU', await read('performance/shared/lru_cache.lua'));
    const lru = await lua.doString(`
        local lru = load(__LRU)()
        local c = lru:new(2)
        c:put("a", 1); c:put("b", 2); c:put("c", 3)
        return tostring(c:get("a")) .. "," .. tostring(c:get("b")) .. "," .. tostring(c:get("c"))
    `);
    assert(lru === 'nil,2,3', `lru_cache evicts the oldest entry (got "${lru}", expected "nil,2,3")`);

    // zod validation (root schema is an object field_def; validate returns ok, errStr)
    lua.global.set('__ZOD', await read('performance/shared/zod.lua'));
    const zod = await lua.doString(`
        local zod = load(__ZOD)()
        local schema = zod:new({
            type = "object",
            properties = { name = { type = "string" }, age = { type = "number" } }
        })
        local goodOk = schema:validate({ name = "Ke", age = 5 })   -- valid
        local badOk  = schema:validate({ name = 123,  age = 5 })   -- name not a string
        return tostring(goodOk) .. "/" .. tostring(badOk)
    `);
    assert(zod === 'true/false', `zod accepts a valid payload and rejects an invalid one (got "${zod}", expected "true/false")`);

    lua.global.close();
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Negative control — load the PRE-FIX manager.lua (git HEAD) and prove the
//    same tests FAIL there. This confirms the tests above actually discriminate.
// ─────────────────────────────────────────────────────────────────────────────
async function testNegativeControl() {
    console.log('\n\x1b[1m[7] Negative control — pre-fix manager.lua (git HEAD) must misbehave\x1b[0m');
    let oldSrc: string;
    try {
        const { execSync } = await import('child_process');
        oldSrc = execSync(
            'git show HEAD:"resources/[framework]/kecore/internal/shared/events/manager.lua"',
            { encoding: 'utf8' }
        );
    } catch {
        console.log('  \x1b[33m⚠ skipped (could not read HEAD version)\x1b[0m');
        return;
    }

    // Leak: registering 3 handlers for one resource, only the LAST is tracked.
    const vm = await makeKecVM(true, oldSrc);
    vm.lua.global.set('print', () => {});
    vm.setInvokingResource('resA');
    await vm.run('kec:on("e1", function() end)');
    await vm.run('kec:on("e2", function() end)');
    await vm.run('kec:on("e3", function() end)');
    const tokens = [...vm.tokensFor('e1'), ...vm.tokensFor('e2'), ...vm.tokensFor('e3')];
    await vm.fire('onResourceStop', '', 'resA');
    const removedCount = tokens.filter(t => vm.removed(t)).length;
    assert(removedCount < 3, `old code LEAKS handlers (removed only ${removedCount}/3 — the bug)`);
    vm.close();

    // Crash: old onLocal references undefined `shared`, so a throwing callback errors.
    const vm2 = await makeKecVM(false, oldSrc);
    vm2.lua.global.set('print', () => {});
    await vm2.run('kec:onLocal("le", function() error("boom") end)');
    let threw = false;
    try { await vm2.fire('le', ''); } catch { threw = true; }
    assert(threw, 'old code CRASHES on a throwing local callback (indexes nil `shared` — the bug)');
    vm2.close();
}

async function main() {
    console.log('\x1b[1m\x1b[36mKeCore Lua test harness (wasmoon · Lua 5.4 · mocked CfxLua)\x1b[0m');
    await testSyntax();
    await testHandlerLeak();
    await testDebugFlag();
    await testCallbackErrorIsolation();
    await testResourceStartContext();
    await testPerformanceModules();
    await testNegativeControl();

    console.log(`\n\x1b[1mResult:\x1b[0m \x1b[32m${passed} passed\x1b[0m, ${failed ? `\x1b[31m${failed} failed\x1b[0m` : '0 failed'}`);
    process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error('Harness error:', e); process.exit(2); });

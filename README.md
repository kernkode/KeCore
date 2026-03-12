<div align="center">
  <h1>🚀 KeCore 2.0</h1>
  <p><b>Build fast. Stay safe. Scale freely.</b></p>
  <p>The definitive framework for FiveM, powered by Bun.</p>
</div>

---

## 🎯 What is KeCore?

Traditional FiveM development is often plagued by slow server restarts, spaghetti code, security vulnerabilities, and complex setups that steal your time away from what truly matters: **building incredible experiences for your players**.

**KeCore** was born to break that cycle. It is a modern, rock-solid, and blazingly fast framework designed from the ground up to radically change how you develop on FiveM. Built on top of **Bun 1.x**, KeCore provides an environment where speed, security, and Developer Experience (DX) mark a before and after in your workflow.

## 💡 Why use KeCore? (The End of the Headache)

If you are tired of restarting your server for every minor change or living in fear of modder injections and exploits, KeCore is your new tool of choice. Here are the reasons to make the jump:

### ⚡ Unmatched Speed (True Hot Reload)
Forget about compiling, bundling, and restarting. Thanks to the Bun engine, KeCore cold-starts in less than a second. But the real magic is its **True Hot Reload**: edit any `.ts` or `.lua` file and see the changes reflected **instantly** live. No script restarts, no lost state variables. You get in the zone, and you stay in the zone.

### 🛡️ Secure by Design (Zero-Trust)
In FiveM, you cannot trust the client, and KeCore assumes this at its core.
- **Runtime Zod:** Through `kec.zod`, strict data contracts are enforced on every payload that crosses the network.
- **Secure RPC:** Events and remote procedure calls come with solid client/server boundaries, origin checks, and invalidation of malicious data. Eliminate ghost triggers from day one.

### 🧰 Batteries Included
Development shouldn't require wasting a week piecing together standalone libraries. KeCore comes out of the box with everything ready to use:
- **Database:** Fluent query builder and native integration with MongoDB.
- **Networking:** Clean, built-in modules for HTTP requests.
- **Optimization:** In-memory LRU Cache with precise expiration control (TTL).
- **Communication:** An asynchronous, highly-typed RPC system with configurable timeouts.

### 🏭 Production Ready
KeCore is not a proof of concept. Its architecture is built to scale, allowing you to support massive player bases with exceptional performance, all while keeping your codebase clean, modular, and easy to maintain for your entire team.

---

## 🚀 Start Building

Stop fighting your infrastructure and spend your time building features your players will love.

📚 **[Check out the Official Documentation](https://kecore-docs.vercel.app/)**

<br>

<div align="center">
  <sub>MIT Licensed • Built with ❤️ for the FiveM community.</sub>
</div>

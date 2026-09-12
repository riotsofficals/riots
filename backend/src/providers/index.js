import { luaprot } from './luaprot.js';

/**
 * Provider registry — supports multiple key APIs.
 * LuaProt is the primary/first provider. To add another (e.g. Luarmor),
 * create ./luarmor.js exposing the same method surface and register it here.
 *
 * Every provider should implement:
 *   fetchKeys, keyInfo, addKey, generateKeys, updateKey,
 *   blacklistKey, unblacklistKey, deleteKey, resetHwid
 */
const registry = new Map();

function register(provider) {
  registry.set(provider.id, provider);
}

register(luaprot);
// register(luarmor);   // <- add later

export function getProvider(id) {
  const p = registry.get(id);
  if (!p) {
    const err = new Error(`Unknown key provider: ${id}`);
    err.status = 400;
    throw err;
  }
  return p;
}

export function listProviders() {
  return [...registry.values()].map((p) => ({ id: p.id, label: p.label }));
}

// Default provider used when the client doesn't specify one.
export const DEFAULT_PROVIDER = 'luaprot';

import { config } from '../config.js';

/**
 * LuaProt provider adapter.
 * Docs: https://docs.luaprot.net/luaprot/api-documentation
 *
 * IMPORTANT: LuaProt requires the IP that makes these requests to be
 * whitelisted on the dashboard. On Railway that is your service's egress
 * IP. Requests from non-whitelisted IPs are rejected.
 *
 * Rate limit: 20 req / 10s and 60 req / min (429 on exceed).
 */

const BASE = config.luaprot.baseUrl;

function headers() {
  return {
    'Content-Type': 'application/json',
    Authorization: config.luaprot.apiKey,
  };
}

async function call(method, urlPath, { query, body } = {}) {
  if (!config.luaprot.apiKey) {
    const err = new Error('LuaProt API key is not configured.');
    err.status = 503;
    throw err;
  }
  const url = new URL(urlPath, BASE);
  if (query) {
    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, String(v));
    }
  }
  const res = await fetch(url, {
    method,
    headers: headers(),
    body: body ? JSON.stringify(body) : undefined,
  });

  let data;
  try {
    data = await res.json();
  } catch {
    data = { success: false, message: `Non-JSON response (${res.status})` };
  }

  if (res.status === 429) {
    const err = new Error('Rate limited by LuaProt. Try again shortly.');
    err.status = 429;
    throw err;
  }
  if (!res.ok || data.success === false) {
    const err = new Error(data.message || `LuaProt request failed (${res.status})`);
    err.status = res.ok ? 400 : res.status;
    err.provider = 'luaprot';
    throw err;
  }
  return data;
}

const hubId = () => config.luaprot.hubId;

export const luaprot = {
  id: 'luaprot',
  label: 'LuaProt',

  // List hubs + scripts linked to the account
  async getHubs() {
    return call('GET', '/api/v1/hubs/get');
  },

  // Fetch keys with optional filters (discordId, key, hwid, active, etc.)
  async fetchKeys(filters = {}) {
    return call('GET', '/api/v1/keys/fetch', { query: filters });
  },

  // Info for a single key (by discordId OR key)
  async keyInfo({ discordId, key }) {
    return call('GET', `/api/v1/hubs/${hubId()}/keys/info`, {
      query: { discordId, key },
    });
  },

  // Create/assign a key to a discord user
  async addKey({ discordId, expire, note, limitedScripts }) {
    return call('POST', `/api/v2/hubs/${hubId()}/keys/add`, {
      body: { discordId, expire, note, limitedScripts },
    });
  },

  // Generate a batch of unassigned keys (amount 5..300)
  async generateKeys({ amount, expire, note, limitedScripts }) {
    return call('POST', `/api/v2/hubs/${hubId()}/keys/generate`, {
      body: { amount, expire, note, limitedScripts },
    });
  },

  // Update a key (by discordId OR key). Also used for blacklist toggling.
  async updateKey({ discordId, key }, patch) {
    return call('PATCH', `/api/v2/hubs/${hubId()}/keys/update`, {
      query: { discordId, key },
      body: patch,
    });
  },

  async blacklistKey({ discordId, key }, reason) {
    return this.updateKey({ discordId, key }, {
      blacklisted: true,
      blacklistReason: reason || 'Blacklisted by admin',
    });
  },

  async unblacklistKey({ discordId, key }) {
    return this.updateKey({ discordId, key }, { blacklisted: false });
  },

  async deleteKey({ discordId, key }) {
    return call('DELETE', `/api/v1/hubs/${hubId()}/keys/delete`, {
      query: { discordId, key },
    });
  },

  async bulkDelete(keys) {
    return call('POST', '/api/v1/keys/bulk-delete', { body: keys });
  },

  // Force a HWID reset (by discordId OR key)
  async resetHwid({ discordId, key, enforceCooldown }) {
    return call('PATCH', `/api/v1/hubs/${hubId()}/hwid/reset`, {
      query: { discordId, key, enforceCooldown },
    });
  },

  // Increment execution count for a key (called by external loader)
  async incrementExecutionCount({ discordId, key }) {
    // LuaProt may not have a dedicated endpoint for this
    // The execution count is typically tracked on their side when keys are used
    // We'll implement a local workaround by fetching and updating
    try {
      const info = await this.keyInfo({ discordId, key });
      const k = info.key;
      if (k) {
        return this.updateKey({ discordId, key }, {
          executionCount: (k.executionCount || 0) + 1,
          lastExecution: Math.floor(Date.now() / 1000),
        });
      }
    } catch (e) {
      // Silently fail - execution count is not critical
      console.warn('[luaprot] Failed to increment execution count:', e.message);
    }
    return { success: true };
  },
};

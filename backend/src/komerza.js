import { config } from './config.js';

/**
 * Komerza REST API helper (server-side only).
 * Docs: https://docs.komerza.com/api-reference
 *
 * The API key is a SECRET (Bearer token). It only ever lives here, in the
 * backend env. The frontend never sees it — it just asks this backend for
 * things like live stock.
 */

const BASE = config.komerza.baseUrl;

async function call(path) {
  if (!config.komerza.apiKey || !config.komerza.storeId) {
    const err = new Error('Komerza API not configured.');
    err.status = 503;
    throw err;
  }
  const res = await fetch(new URL(path, BASE), {
    headers: {
      Authorization: `Bearer ${config.komerza.apiKey}`,
      'Content-Type': 'application/json',
    },
  });
  let data;
  try { data = await res.json(); } catch { data = {}; }
  if (!res.ok || data.success === false) {
    const err = new Error(data.message || `Komerza request failed (${res.status})`);
    err.status = res.status || 500;
    throw err;
  }
  return data;
}

export const komerza = {
  // Fetch a product (includes its variants + per-variant stock).
  async getProduct(productId) {
    const id = productId || config.komerza.productId;
    return call(`/stores/${config.komerza.storeId}/products/${id}`);
  },

  /**
   * Return a lightweight, PUBLIC-SAFE stock summary for a product.
   * Only exposes what a shopper is allowed to see (stock counts + in-stock
   * flag), never internal fields, files, keys, etc.
   */
  async getStock(productId) {
    const result = await this.getProduct(productId);
    const p = result.data || {};
    const hideStock = !!p.hideStock;
    const variants = (p.variants || []).map((v) => ({
      id: v.id,
      name: v.name,
      // stockMode 0 usually = unlimited; when hidden, don't leak the number
      stock: hideStock ? null : (typeof v.stock === 'number' ? v.stock : null),
      inStock: v.stockMode === 0 ? true : (typeof v.stock === 'number' ? v.stock > 0 : true),
    }));
    const anyInStock = variants.some((v) => v.inStock);
    return {
      productId: p.id,
      name: p.name,
      hideStock,
      inStock: anyInStock,
      variants,
    };
  },
};

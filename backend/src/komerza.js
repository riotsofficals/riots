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

async function call(path, { method = 'GET', body } = {}) {
  if (!config.komerza.apiKey || !config.komerza.storeId) {
    const err = new Error('Komerza API not configured.');
    err.status = 503;
    throw err;
  }
  const res = await fetch(new URL(path, BASE), {
    method,
    body: body ? JSON.stringify(body) : undefined,
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
    const productHideStock = !!p.hideStock;
    const variants = (p.variants || []).map((v) => {
      // Komerza's authoritative flag: isOutOfStock is true only when stock
      // tracking is on AND stock is zero; it's always false when stock is
      // hidden or untracked (e.g. Ignored mode / files). So inStock is just
      // the inverse — this is what fixes "empty when it isn't".
      const inStock = v.isOutOfStock !== true;
      const hideStock = productHideStock || !!v.hideStock;
      return {
        id: v.id,
        name: v.name,
        stock: hideStock ? null : (typeof v.stock === 'number' ? v.stock : null),
        inStock,
      };
    });
    // If the product has no variants array (single-variant edge cases), treat
    // it as in stock rather than falsely empty.
    const anyInStock = variants.length ? variants.some((v) => v.inStock) : true;
    return {
      productId: p.id,
      name: p.name,
      hideStock: productHideStock,
      inStock: anyInStock,
      variants,
    };
  },

  /**
   * List real orders/sales for the store. Komerza list endpoints return
   * everything by default and support filtering via query params. We pass an
   * optional limit/status through. Returns the raw Komerza response so the
   * caller can normalise (order shapes vary a little between events).
   */
  async listOrders({ limit, status } = {}) {
    const qs = new URLSearchParams();
    if (limit) qs.set('limit', String(limit));
    if (status) qs.set('status', String(status));
    const suffix = qs.toString() ? `?${qs.toString()}` : '';
    return call(`/stores/${config.komerza.storeId}/orders${suffix}`);
  },

  /**
   * Fetch orders and roll them up into a PUBLIC-SAFE sales summary for the
   * admin dashboard: total revenue, order counts, and a trimmed recent list.
   * Defensive about field names since Komerza order payloads can vary.
   */
  async getSalesSummary({ limit = 100 } = {}) {
    const result = await this.listOrders({ limit });
    // Orders can live at data, data.orders, data.items, or the root array.
    let raw = result?.data ?? result ?? [];
    if (!Array.isArray(raw)) raw = raw.orders || raw.items || raw.data || [];
    if (!Array.isArray(raw)) raw = [];

    const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
    const paidStatuses = ['completed', 'paid', 'fulfilled', 'delivered', 'complete'];

    const orders = raw.map((o) => {
      const status = String(o.status ?? o.state ?? o.paymentStatus ?? '').toLowerCase();
      const amount = num(o.total ?? o.amount ?? o.cost ?? o.totalAmount ?? o.grandTotal ?? 0);
      const items = Array.isArray(o.items) ? o.items : [];
      const productName =
        o.productName ??
        items[0]?.productName ??
        items[0]?.name ??
        (items.length ? `${items.length} item${items.length > 1 ? 's' : ''}` : '—');
      return {
        id: o.id ?? o.orderId ?? o.reference ?? '',
        status,
        paid: paidStatuses.some((s) => status.includes(s)),
        refunded: status.includes('refund'),
        amount,
        currency: o.currency ?? o.currencyCode ?? 'USD',
        gateway: o.gateway ?? o.paymentMethod ?? o.method ?? '',
        email: o.emailAddress ?? o.email ?? o.customer?.email ?? '',
        product: productName,
        quantity: items.reduce((n, it) => n + num(it.quantity ?? 1), 0) || 1,
        createdAt: o.createdAt ?? o.created ?? o.date ?? o.timestamp ?? null,
      };
    });

    const paid = orders.filter((o) => o.paid && !o.refunded);
    const revenue = paid.reduce((sum, o) => sum + o.amount, 0);
    const currency = orders.find((o) => o.currency)?.currency || 'USD';

    // Revenue in the last 30 days (only orders with a parseable date).
    const now = Date.now();
    const dayMs = 24 * 60 * 60 * 1000;
    let revenue30 = 0, orders30 = 0;
    for (const o of paid) {
      const t = o.createdAt ? new Date(o.createdAt).getTime() : NaN;
      if (Number.isFinite(t) && now - t <= 30 * dayMs) { revenue30 += o.amount; orders30 += 1; }
    }

    const recent = orders
      .slice()
      .sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0))
      .slice(0, 25);

    return {
      currency,
      totals: {
        orders: orders.length,
        paidOrders: paid.length,
        refunded: orders.filter((o) => o.refunded).length,
        revenue: Math.round(revenue * 100) / 100,
        revenue30: Math.round(revenue30 * 100) / 100,
        orders30,
        avgOrder: paid.length ? Math.round((revenue / paid.length) * 100) / 100 : 0,
      },
      recent,
    };
  },
};

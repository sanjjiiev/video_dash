'use strict';

/**
 * middleware/rbac.js — Role-Based Access Control + Subscription gating.
 *
 * Usage:
 *   router.get('/premium-content', requireAuth, requireSubscription('pro'), handler)
 *   router.delete('/video/:id',    requireAuth, requireRole('admin'),         handler)
 */

const createError = require('http-errors');

// ── Role hierarchy ────────────────────────────────────────────────────────────
const ROLE_RANK = { viewer: 0, creator: 1, moderator: 2, admin: 3 };

/**
 * Require the authenticated user to have at least the specified role.
 * Must be placed AFTER requireAuth (which populates req.user).
 */
function requireRole(minRole) {
  return (req, res, next) => {
    const userRank = ROLE_RANK[req.user?.role] ?? -1;
    const minRank  = ROLE_RANK[minRole]        ?? 999;

    if (userRank < minRank) {
      return next(createError(403, `Requires '${minRole}' role`));
    }
    next();
  };
}

// ── Subscription tier hierarchy ───────────────────────────────────────────────
const PLAN_RANK = { free: 0, pro: 1, premium: 2 };

/**
 * Require the authenticated user to have an active subscription at or above
 * the specified tier.
 *
 * Checks:
 *  1. user.subscription_plan rank >= required rank
 *  2. user.subscription_expires_at is null (lifetime) or in the future
 */
function requireSubscription(minPlan) {
  return (req, res, next) => {
    const user     = req.user;
    const userRank = PLAN_RANK[user?.subscription_plan] ?? 0;
    const minRank  = PLAN_RANK[minPlan]                 ?? 999;

    if (userRank < minRank) {
      return next(createError(402, {
        message:  `This content requires a '${minPlan}' subscription`,
        code:     'SUBSCRIPTION_REQUIRED',
        requires: minPlan,
        current:  user?.subscription_plan ?? 'free',
      }));
    }

    // Check expiry (null = lifetime / no expiry)
    if (user?.subscription_expires_at) {
      const expired = new Date(user.subscription_expires_at) < new Date();
      if (expired) {
        return next(createError(402, {
          message: 'Your subscription has expired',
          code:    'SUBSCRIPTION_EXPIRED',
        }));
      }
    }

    next();
  };
}

/**
 * requireOwnership — ensures the authenticated user owns a resource.
 * The resource's owner field is resolved by the provided async function.
 *
 * Example:
 *   requireOwnership(async (req, db) => {
 *     const { rows } = await db.query('SELECT owner_id FROM videos WHERE id=$1', [req.params.id]);
 *     return rows[0]?.owner_id;
 *   })
 */
function requireOwnership(getOwnerId) {
  return async (req, res, next) => {
    try {
      const db      = require('../db');
      const ownerId = await getOwnerId(req, db);

      if (!ownerId) return next(createError(404, 'Resource not found'));

      // Admins bypass ownership checks
      if (ROLE_RANK[req.user?.role] >= ROLE_RANK.admin) return next();

      if (ownerId !== req.user?.id) {
        return next(createError(403, 'You do not own this resource'));
      }
      next();
    } catch (err) {
      next(err);
    }
  };
}

module.exports = { requireRole, requireSubscription, requireOwnership, ROLE_RANK, PLAN_RANK };

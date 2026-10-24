/*
 * Guidance policy resolver: decides allow / guided / block for a site.
 *
 * Shared by the Safari extension (loaded as a classic script, exposed as
 * globalThis.GuidanceResolver) and the backend test suite (via require).
 * Keep it dependency-free.
 *
 * Precedence: approved "Ask a parent" request → master "AI off" → per-site override →
 * active schedule → category setting.
 */
(function (root) {
  "use strict";

  var STRICTNESS = { allow: 0, guided: 1, block: 2 };

  function normalizeHost(host) {
    return String(host || "").trim().toLowerCase().replace(/\.$/, "");
  }

  function matchesDomain(host, domain) {
    return host === domain || host.endsWith("." + domain);
  }

  /** Longest matching key wins, so "chat.deepseek.com" beats "deepseek.com". */
  function longestMatch(host, domains) {
    var best = null;
    for (var i = 0; i < domains.length; i++) {
      var d = domains[i];
      if (matchesDomain(host, d) && (!best || d.length > best.length)) best = d;
    }
    return best;
  }

  function toMinutes(hhmm) {
    var parts = String(hhmm).split(":");
    return Number(parts[0]) * 60 + Number(parts[1]);
  }

  /** Days use Date.getDay(): 0 = Sunday. Windows where end < start run past midnight. */
  function scheduleIsActive(schedule, now) {
    if (!schedule || schedule.enabled === false) return false;
    var day = now.getDay();
    var minute = now.getHours() * 60 + now.getMinutes();
    var start = toMinutes(schedule.start);
    var end = toMinutes(schedule.end);
    var days = schedule.days || [];
    if (start === end) return days.indexOf(day) !== -1;
    if (start < end) return days.indexOf(day) !== -1 && minute >= start && minute < end;
    var yesterday = (day + 6) % 7;
    return (days.indexOf(day) !== -1 && minute >= start) || (days.indexOf(yesterday) !== -1 && minute < end);
  }

  function activeSchedules(policy, now) {
    return (policy.schedules || []).filter(function (s) {
      return scheduleIsActive(s, now);
    });
  }

  function categoryForHost(host, catalog) {
    var best = null;
    var bestLength = 0;
    (catalog.categories || []).forEach(function (category) {
      var d = longestMatch(host, category.domains || []);
      if (d && d.length > bestLength) {
        best = category;
        bestLength = d.length;
      }
    });
    return best;
  }

  /**
   * Current state for every category, plus whether AI is off entirely.
   * When several active schedules set the same category, the strictest wins.
   */
  function effectiveState(policy, catalog, now) {
    var states = {};
    var sources = {};
    (catalog.categories || []).forEach(function (c) {
      var set = policy.categories && policy.categories[c.id];
      states[c.id] = set || c.defaultState || "allow";
      sources[c.id] = "category";
    });

    var masterOff = Boolean(policy.masterAIOff);
    var masterSource = masterOff ? "master" : null;
    var scheduled = {};
    var active = activeSchedules(policy, now);

    active.forEach(function (s) {
      if (s.masterAIOff && !masterOff) {
        masterOff = true;
        masterSource = "schedule:" + s.name;
      }
      Object.keys(s.categories || {}).forEach(function (id) {
        var value = s.categories[id];
        if (!(id in scheduled) || STRICTNESS[value] > STRICTNESS[scheduled[id].value]) {
          scheduled[id] = { value: value, name: s.name };
        }
      });
    });

    Object.keys(scheduled).forEach(function (id) {
      states[id] = scheduled[id].value;
      sources[id] = "schedule:" + scheduled[id].name;
    });

    return {
      masterOff: masterOff,
      masterSource: masterSource,
      states: states,
      sources: sources,
      activeScheduleNames: active.map(function (s) {
        return s.name;
      }),
    };
  }

  /** Approved requests still running at `now`, as { domain: untilISO }. */
  function activeTemporaryAllows(policy, now) {
    var out = {};
    (policy.temporaryAllows || []).forEach(function (t) {
      if (Date.parse(t.until) > now.getTime()) out[t.domain] = t.until;
    });
    return out;
  }

  /**
   * Resolve one hostname.
   * Returns { state, categoryId, source } where source is "approved", "master",
   * "override", "schedule:<name>", "category", or "none" (not an AI site we know about).
   * An approved request also returns `until`.
   */
  function resolveSite(host, policy, catalog, now, effective) {
    host = normalizeHost(host);
    now = now || new Date();
    var eff = effective || effectiveState(policy, catalog, now);
    var category = categoryForHost(host, catalog);
    var overrides = policy.siteOverrides || {};
    var overrideDomain = longestMatch(host, Object.keys(overrides));
    var categoryId = category ? category.id : null;

    var approved = activeTemporaryAllows(policy, now);
    var approvedDomain = longestMatch(host, Object.keys(approved));
    if (approvedDomain) {
      return { state: "allow", categoryId: categoryId, source: "approved", until: approved[approvedDomain] };
    }

    if (eff.masterOff && (category || overrideDomain)) {
      return { state: "block", categoryId: categoryId, source: eff.masterSource || "master" };
    }
    if (overrideDomain) {
      return { state: overrides[overrideDomain], categoryId: categoryId, source: "override" };
    }
    if (!category) {
      return { state: "allow", categoryId: null, source: "none" };
    }
    return { state: eff.states[category.id], categoryId: category.id, source: eff.sources[category.id] };
  }

  /**
   * Every domain the extension needs a rule for, with its resolved state.
   * Used to build Safari declarativeNetRequest rules.
   */
  function resolveAll(policy, catalog, now) {
    now = now || new Date();
    var eff = effectiveState(policy, catalog, now);
    var domains = {};
    (catalog.categories || []).forEach(function (c) {
      (c.domains || []).forEach(function (d) {
        domains[d] = true;
      });
    });
    Object.keys(policy.siteOverrides || {}).forEach(function (d) {
      domains[d] = true;
    });
    (policy.temporaryAllows || []).forEach(function (t) {
      domains[t.domain] = true;
    });
    return Object.keys(domains)
      .sort()
      .map(function (d) {
        var r = resolveSite(d, policy, catalog, now, eff);
        return { domain: d, state: r.state, categoryId: r.categoryId, source: r.source };
      });
  }

  var api = {
    normalizeHost: normalizeHost,
    matchesDomain: matchesDomain,
    scheduleIsActive: scheduleIsActive,
    activeSchedules: activeSchedules,
    activeTemporaryAllows: activeTemporaryAllows,
    categoryForHost: categoryForHost,
    effectiveState: effectiveState,
    resolveSite: resolveSite,
    resolveAll: resolveAll,
  };

  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else {
    root.GuidanceResolver = api;
  }
})(typeof globalThis !== "undefined" ? globalThis : this);

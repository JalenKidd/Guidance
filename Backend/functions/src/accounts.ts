import { timingSafeEqual } from "node:crypto";
import type { Family, Store } from "./store.js";

/**
 * Demo sign-in for the competition build: four made-up parent accounts, one family
 * each, sharing one password. Not real authentication.
 */
export const DEMO_ACCOUNTS = [
  { email: "marvespaztanes@gmail.com", name: "Marves" },
  { email: "jalenpaztanes@gmail.com", name: "Jalen" },
  { email: "miguelpaztanes@gmail.com", name: "Miguel" },
  { email: "alanipaztanes@gmail.com", name: "Alani" },
] as const;

/** Marves's account takes over the family that was set up before accounts existed. */
const ADOPTS_EXISTING_FAMILY = "marvespaztanes@gmail.com";

export function demoPassword(): string {
  return process.env.DEMO_PASSWORD || "guidance123";
}

export function passwordMatches(given: string, expected = demoPassword()): boolean {
  const a = Buffer.from(given);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

export function isDemoAccount(email: string): boolean {
  const e = email.trim().toLowerCase();
  return DEMO_ACCOUNTS.some((a) => a.email === e);
}

/**
 * Give each demo account a family. Safe to run on every start: accounts that
 * already have a family are left alone.
 */
export function seedDemoAccounts(store: Store): void {
  const linked = new Set(DEMO_ACCOUNTS.map((a) => store.familyForAccount(a.email)?.id).filter(Boolean));

  for (const account of DEMO_ACCOUNTS) {
    if (store.familyForAccount(account.email)) continue;

    let family: Family | undefined;
    if (account.email === ADOPTS_EXISTING_FAMILY) {
      const unlinked = store.allFamilies().filter((f) => !linked.has(f.id));
      family =
        unlinked.find((f) => f.kids.some((k) => k.deviceToken)) ??
        [...unlinked].sort((a, b) => a.createdAt.localeCompare(b.createdAt))[0];
    }
    family ??= store.createFamily(account.name);
    if (!family.parentName) store.setParentName(family, account.name);

    store.linkAccount(account.email, family);
    linked.add(family.id);
  }
}

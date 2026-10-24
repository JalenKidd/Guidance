import { randomBytes, randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import type { KidPolicy } from "./validation.js";

export interface Kid {
  id: string;
  name: string;
  pairingCode: string;
  /** Set once the kid's Safari extension pairs; the extension authenticates with it. */
  deviceToken?: string;
  policy: KidPolicy;
  lastHeartbeat?: string;
  createdAt: string;
}

export interface Family {
  id: string;
  parentToken: string;
  /** Shown to the kid as "Guardian: <name>" in the Safari extension. */
  parentName?: string;
  kids: Kid[];
  createdAt: string;
}

export type ActivityType = "blocked" | "guided_block" | "guided_allow" | "answer_hidden" | "safety_alert";

export interface ActivityEvent {
  id: string;
  kidId: string;
  type: ActivityType;
  domain?: string;
  categoryId?: string;
  reason?: string;
  /** Safety alerts only: which topic, how urgent, and the kid's message. */
  topic?: string;
  severity?: "urgent" | "notice";
  excerpt?: string;
  at: string;
}

export interface AccessRequest {
  id: string;
  kidId: string;
  domain: string;
  categoryId?: string;
  kind: "site" | "guided";
  reason: string;
  minutes: number;
  status: "pending" | "approved" | "denied";
  createdAt: string;
  decidedAt?: string;
  /** When an approval runs out. */
  until?: string;
}

export interface Suggestion {
  familyId: string;
  domain: string;
  categoryId?: string;
  note?: string;
  at: string;
}

interface StoreData {
  families: Record<string, Family>;
  events: ActivityEvent[];
  suggestions: Suggestion[];
  requests: AccessRequest[];
  /** Demo sign-in: lowercase email → family id. */
  accounts: Record<string, string>;
}

const MAX_EVENTS_PER_KID = 500;
const MAX_PENDING_REQUESTS_PER_KID = 10;
const MAX_REQUESTS_PER_KID = 100;
const PAIRING_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O or 1/I

export function newToken(): string {
  return randomBytes(24).toString("base64url");
}

export function newPairingCode(): string {
  const bytes = randomBytes(6);
  return Array.from(bytes, (b) => PAIRING_ALPHABET[b % PAIRING_ALPHABET.length]).join("");
}

/**
 * JSON-file store for the demo backend. Everything lives in memory and is written
 * through to `path` on each change; with no path it is memory-only (tests).
 * Swap for Firebase/Postgres behind the same methods later.
 */
export class Store {
  private data: StoreData = { families: {}, events: [], suggestions: [], requests: [], accounts: {} };

  constructor(private readonly path?: string) {
    if (path && existsSync(path)) {
      this.data = { ...this.data, ...JSON.parse(readFileSync(path, "utf8")) };
    }
  }

  private persist() {
    if (!this.path) return;
    mkdirSync(dirname(this.path), { recursive: true });
    const tmp = `${this.path}.tmp`;
    writeFileSync(tmp, JSON.stringify(this.data, null, 2));
    renameSync(tmp, this.path);
  }

  createFamily(parentName?: string): Family {
    const family: Family = { id: randomUUID(), parentToken: newToken(), parentName, kids: [], createdAt: new Date().toISOString() };
    this.data.families[family.id] = family;
    this.persist();
    return family;
  }

  family(id: string): Family | undefined {
    return this.data.families[id];
  }

  allFamilies(): Family[] {
    return Object.values(this.data.families);
  }

  linkAccount(email: string, family: Family) {
    this.data.accounts[email.toLowerCase()] = family.id;
    this.persist();
  }

  familyForAccount(email: string): Family | undefined {
    const id = this.data.accounts[email.trim().toLowerCase()];
    return id ? this.data.families[id] : undefined;
  }

  renameKid(kid: Kid, name: string) {
    kid.name = name;
    this.persist();
  }

  familyOfKid(kidId: string): Family | undefined {
    return Object.values(this.data.families).find((f) => f.kids.some((k) => k.id === kidId));
  }

  setParentName(family: Family, parentName: string) {
    family.parentName = parentName;
    this.persist();
  }

  addKid(family: Family, name: string, policy: KidPolicy): Kid {
    let code = newPairingCode();
    while (this.kidByPairingCode(code)) code = newPairingCode();
    const kid: Kid = { id: randomUUID(), name, pairingCode: code, policy, createdAt: new Date().toISOString() };
    family.kids.push(kid);
    this.persist();
    return kid;
  }

  removeKid(family: Family, kidId: string): boolean {
    const before = family.kids.length;
    family.kids = family.kids.filter((k) => k.id !== kidId);
    this.data.events = this.data.events.filter((e) => e.kidId !== kidId);
    this.data.requests = this.data.requests.filter((r) => r.kidId !== kidId);
    this.persist();
    return family.kids.length !== before;
  }

  updatePolicy(kid: Kid, policy: KidPolicy) {
    kid.policy = policy;
    this.persist();
  }

  kidByPairingCode(code: string): Kid | undefined {
    for (const family of Object.values(this.data.families)) {
      const kid = family.kids.find((k) => k.pairingCode === code);
      if (kid) return kid;
    }
    return undefined;
  }

  kidByDeviceToken(token: string): Kid | undefined {
    for (const family of Object.values(this.data.families)) {
      const kid = family.kids.find((k) => k.deviceToken === token);
      if (kid) return kid;
    }
    return undefined;
  }

  /** Pairing replaces any previously paired device for that kid. */
  pairDevice(kid: Kid): string {
    kid.deviceToken = newToken();
    kid.lastHeartbeat = new Date().toISOString();
    this.persist();
    return kid.deviceToken;
  }

  recordHeartbeat(kid: Kid, at = new Date().toISOString()) {
    kid.lastHeartbeat = at;
    this.persist();
  }

  addEvents(events: Omit<ActivityEvent, "id">[]) {
    for (const e of events) this.data.events.push({ id: randomUUID(), ...e });
    const kidIds = new Set(events.map((e) => e.kidId));
    for (const kidId of kidIds) {
      const mine = this.data.events.filter((e) => e.kidId === kidId);
      if (mine.length > MAX_EVENTS_PER_KID) {
        const drop = new Set(mine.slice(0, mine.length - MAX_EVENTS_PER_KID).map((e) => e.id));
        this.data.events = this.data.events.filter((e) => !drop.has(e.id));
      }
    }
    this.persist();
  }

  eventsFor(kidId: string, limit = 100): ActivityEvent[] {
    return this.data.events.filter((e) => e.kidId === kidId).slice(-limit).reverse();
  }

  /**
   * A kid asking to use something. Asking again for the same thing while a request
   * is pending updates that request instead of piling up new ones.
   */
  addRequest(r: Omit<AccessRequest, "id" | "status" | "createdAt">): AccessRequest | undefined {
    const pending = this.data.requests.filter((x) => x.kidId === r.kidId && x.status === "pending");
    const existing = pending.find((x) => x.domain === r.domain && x.kind === r.kind);
    if (existing) {
      Object.assign(existing, { reason: r.reason, minutes: r.minutes, createdAt: new Date().toISOString() });
      this.persist();
      return existing;
    }
    if (pending.length >= MAX_PENDING_REQUESTS_PER_KID) return undefined;

    const request: AccessRequest = { id: randomUUID(), status: "pending", createdAt: new Date().toISOString(), ...r };
    this.data.requests.push(request);
    const mine = this.data.requests.filter((x) => x.kidId === r.kidId);
    if (mine.length > MAX_REQUESTS_PER_KID) {
      const drop = new Set(mine.slice(0, mine.length - MAX_REQUESTS_PER_KID).map((x) => x.id));
      this.data.requests = this.data.requests.filter((x) => !drop.has(x.id));
    }
    this.persist();
    return request;
  }

  request(id: string): AccessRequest | undefined {
    return this.data.requests.find((r) => r.id === id);
  }

  requestsFor(kidId: string, limit = 30): AccessRequest[] {
    return this.data.requests.filter((r) => r.kidId === kidId).slice(-limit).reverse();
  }

  decideRequest(request: AccessRequest, approve: boolean, until?: string) {
    request.status = approve ? "approved" : "denied";
    request.decidedAt = new Date().toISOString();
    request.until = until;
    this.persist();
  }

  addSuggestion(s: Suggestion) {
    this.data.suggestions.push(s);
    this.persist();
  }
}

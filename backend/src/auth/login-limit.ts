// Límite local por dirección; no confía en encabezados de proxy.
export function createLoginAttemptLimiter(now: () => number = Date.now) {
  const entries = new Map<string, { count: number; until: number }>();
  const windowMs = 15 * 60 * 1000;
  return function allow(key: string): boolean {
    const time = now();
    for (const [address, entry] of entries) if (entry.until <= time) entries.delete(address);
    let entry = entries.get(key);
    if (!entry) {
      if (entries.size >= 1000) return false;
      entry = { count: 0, until: time + windowMs };
      entries.set(key, entry);
    }
    if (entry.count >= 10) return false;
    entry.count++;
    return true;
  };
}

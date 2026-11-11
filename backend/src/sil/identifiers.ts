export const silDemoIdentifier = /^DEMO-[A-Z0-9-]{3,16}$/;

export function readSilDemoIdentifiers(text: string): string[] {
  const matches = text.match(/(?<![A-Z0-9-])DEMO-[A-Z0-9-]{3,16}(?![A-Z0-9-])/gi) ?? [];
  return [...new Set(matches.map((id) => id.toUpperCase()))];
}

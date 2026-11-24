/** A setting the stack passes to a function through its environment. */
export function setting(name: string): string {
  const value = process.env[name];
  if (value === undefined || value === '') {
    throw new Error(`The ${name} setting is missing.`);
  }
  return value;
}

/** A setting that must be a whole number above zero. */
export function numberSetting(name: string): number {
  const value = Number(setting(name));
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`The ${name} setting must be a whole number above zero.`);
  }
  return value;
}

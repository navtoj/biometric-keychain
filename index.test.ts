import { describe, expect, test } from 'bun:test';
import packageJson from './package.json';
import { BiometricKeychainError, LAError, OSStatus } from './src/errors';
import { BiometricKeychain } from './src/index';
import usage from "./src/usage.txt" with { type: "text" };

const bk = new BiometricKeychain({
	path: new URL('src/main.swift', import.meta.url).pathname,
});

describe("automatic", () => {
test('wrong path', async () => {
	const fake = new BiometricKeychain({
		path: new URL('fake/main.swift', import.meta.url).pathname,
	});
	const result = await fake.version();
	expect(result).toBeInstanceOf(BiometricKeychainError);
});

test('instance', () => expect(bk).toBeInstanceOf(BiometricKeychain));

test('version', async () =>
	expect(await bk.version()).toBe(packageJson.version));

test('help', async () =>
	expect(await bk.help()).toBe(usage.trim()));
});

describe("manual", () => {
test('delete (no auth)', async () => expect(await bk.delete('key', { strict: false })).toBeInstanceOf(LAError))
test('delete', async () => expect(await bk.delete('key', { strict: false })).toBe(true))

test('get', async () =>
	expect(await bk.get('key')).toBeInstanceOf(BiometricKeychainError));

test('set', async () => expect(await bk.set('key', 'value', { strict: false })).toBe(true))

test('set (strict)', async () => expect(await bk.set('key', 'value', { strict: true })).toBeInstanceOf(OSStatus))

test('get', async () =>
	expect(await bk.get('key')).toEqual('value'));

test('delete', async () => expect(await bk.delete('key', { strict: false })).toBe(true))

test('delete (strict)', async () => expect(await bk.delete('key', { strict: true })).toBeInstanceOf(OSStatus))
})

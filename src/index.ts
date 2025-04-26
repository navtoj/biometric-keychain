import { execa } from 'execa';
import { constants } from 'fs';
import { access } from 'fs/promises';
import {
	BiometricKeychainError,
	LAError,
	OSStatus,
	ScriptError,
} from './errors.ts';

type VerboseErrorRegex =
	| {
			type: 'OSStatus';
			code: string;
	  }
	| {
			type: 'LAError';
			code: string;
			detail: string;
	  }
	| undefined;
const verboseErrorRegex =
	/^\[(?<type>OSStatus|LAError)\]\[(?<code>-?\d+)\](?<detail>.*)/;

export class BiometricKeychain {
	#namespace: string = 'biometric-keychain';
	#path: string = 'node_modules/.bin/biometric-keychain';

	constructor({ path, namespace }: { path?: string; namespace?: string }) {
		if (path !== undefined) {
			if (path.trim().length === 0) throw new Error('Invalid path.');
			this.#path = path;
		}
		if (namespace !== undefined) {
			if (namespace.trim().length === 0)
				throw new Error('Invalid namespace.');
			this.#namespace = namespace;
		}
	}

	async #run(
		args: string[],
		options: { verbose: boolean } = { verbose: true },
	): Promise<string | BiometricKeychainError> {
		// ensure script is ready
		try {
			await access(this.#path, constants.F_OK);
		} catch (err) {
			return new BiometricKeychainError('No script available at path.');
		}
		try {
			await access(this.#path, constants.X_OK);
		} catch (err) {
			return new BiometricKeychainError('Script at path not executable.');
		}

		// ensure args are valid
		if (!args.length || args.some(arg => arg.trim().length === 0))
			throw new Error('Invalid argument(s).');
		if (options.verbose) args.push('--verbose');

		// run script
		const output = await execa(this.#path, args, {
			reject: false,
			// shell: 'zsh',
		});

		// handle output
		switch (output.exitCode) {
			case 0:
				// if (output.stderr) console.log('{ stderr }', output.stderr);
				return output.stdout;
			default:
				// if (output.stdout) console.log('{ stdout }', output.stdout);
				const match = output.stdout.match(verboseErrorRegex)
					?.groups as VerboseErrorRegex;
				if (!match) return new ScriptError(output.stderr);
				switch (match.type) {
					case 'LAError':
						return new LAError(output.stderr || match.code).from(
							match.detail.trim() || match.code,
						);
					case 'OSStatus':
						return new OSStatus(output.stderr || match.code).from(
							match.code,
						);
				}
		}
	}

	async help() {
		return await this.#run(['--help']);
	}
	async version() {
		return await this.#run(['--version']);
	}
	async get(key: string) {
		return await this.#run(['get', this.#namespace, key]);
	}
	async set(
		key: string,
		value: string,
		options: { strict?: boolean } = { strict: false },
	) {
		const input = ['set', this.#namespace, key, value];
		if (options.strict) input.push('--strict');

		const output = await this.#run(input);
		if (output instanceof BiometricKeychainError) {
			return output;
		}
		return output === 'true' ? true : false;
	}
	async delete(
		key: string,
		options: { strict?: boolean } = { strict: false },
	) {
		const input = ['delete', this.#namespace, key];
		if (options.strict) input.push('--strict');

		const output = await this.#run(input);
		if (output instanceof BiometricKeychainError) {
			return output;
		}
		return output === 'true' ? true : false;
	}
}

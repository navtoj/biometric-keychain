// https://edg.foo/blog/better-errors-ts
export class BiometricKeychainError extends Error {
	constructor(message: string) {
		super(message);
		Object.defineProperty(this, 'name', { value: new.target.name });
		Object.setPrototypeOf(this, new.target.prototype);
	}

	from(cause: unknown): BiometricKeychainError {
		this.cause = cause;
		return this;
	}
}

// manual
export class ScriptError extends BiometricKeychainError {
	constructor(message?: string) {
		super(message ?? new.target.name);
	}
}

// keychain
export class OSStatus extends BiometricKeychainError {
	constructor(message?: string) {
		super(message ?? new.target.name);
	}
}

// authentication
export class LAError extends BiometricKeychainError {
	constructor(message?: string) {
		super(message ?? new.target.name);
	}
}

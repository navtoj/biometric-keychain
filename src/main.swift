#!/usr/bin/env swift
import Foundation
import LocalAuthentication

// Handle Signals

let signalHandler: @convention(c) (Int32) -> Void = { _ in
	EXIT(stderr: "")
}

signal(SIGINT, signalHandler)
signal(SIGQUIT, signalHandler)
signal(SIGHUP, signalHandler)
signal(SIGTERM, signalHandler)

// Handle Base Cases

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--version" {
	// package.json.version
	EXIT(stdout: "1.0.8")
}

if arguments.isEmpty || arguments.first == "--help" {
	EXIT(stdout:
		"""
		Usage:
		    get    <namespace> <key>
		    set    <namespace> <key> <value> [--strict]
		    delete <namespace> <key> [--strict]

		Arguments:
		    <namespace> A unique value used to prevent storage conflicts.
		    <key>       The key to operate on.
		    <value>     The value to store (only for 'set').
		    --strict    Optional boolean flag (true/false). Defaults to false.
		                 - For 'set': If the key already exists, the command will fail.
		                 - For 'delete': If the key does not exist, the command will fail.

		Examples:
		    set    namespace key value
		    set    namespace key value --strict
		    get    namespace key
		    delete namespace key
		    delete namespace key --strict
		"""
	)
}

// Validate Script Input

guard let input = parse(args: arguments) else {
	EXIT(stderr: "Invalid arguments. Use -h or --help for usage information.")
}

// Configure Authentication

let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
let context = LAContext()
context.localizedFallbackTitle = ""
context.touchIDAuthenticationAllowableReuseDuration = LATouchIDAuthenticationMaximumAllowableReuseDuration

// Check Biometric Support

var contextError: NSError?
guard context.canEvaluatePolicy(policy, error: &contextError) else {
	if let error = contextError as? LAError {
		EXIT(error: error, verbose: input.verbose)
	}
	if input.verbose {
		print("[Unknown Error][canEvaluatePolicy]")
	}
	EXIT(stderr: "Biometric authentication not available.")
}

// Ask for Authentication

let reason = switch input.type {
case .get:
	"read from"
case .set:
	"write to"
case .delete:
	"delete from"
}

do {
	try await context.evaluatePolicy(policy, localizedReason: "\(reason) macOS Keychain")
} catch let error as LAError {
	EXIT(error: error, verbose: input.verbose)
} catch {
	if input.verbose {
		print("[Unknown Error][evaluatePolicy]")
	}
	EXIT(stderr: error.localizedDescription)
}

// Perform Operation

let keychain = Keychain(context: context)
let result: Result<String, KeychainError>
switch input.type {
case .get:
	let output = keychain.get(
		namespace: input.namespace,
		account: input.key
	)
	result = normalize(result: output)
case let .set(value: value):
	let output = keychain.set(
		namespace: input.namespace,
		account: input.key,
		value: value,
		strict: input.strict
	)
	result = normalize(result: output)
case .delete:
	let output = keychain.delete(
		namespace: input.namespace,
		account: input.key,
		strict: input.strict
	)
	result = normalize(result: output)
}

// Handle Result

if case let .success(value) = result {
	EXIT(stdout: value)
} else if case let .failure(error) = result {
	if input.verbose {
		if case let .unhandled(status) = error {
			print("[OSStatus][\(status)]")
		} else {
			print("[Error][\(error)]")
		}
	}
	EXIT(stderr: error.localizedDescription)
}

// Utilities

enum KeychainError: Error, LocalizedError {
	case unhandled(status: OSStatus)
	case setValueInvalid
	case getValueInvalid

	// print(error.localizedDescription)
	var errorDescription: String? {
		switch self {
		case let .unhandled(status):
			guard let message = SecCopyErrorMessageString(status, nil) as String? else {
				return "Unknown keychain error."
			}
			return message
		case .setValueInvalid:
			return "The provided value is invalid."
		case .getValueInvalid:
			return "The saved value could not be parsed."
		}
	}

	// print(error)
	var debugDescription: String {
		switch self {
		default:
			return "\(self)"
		}
	}
}

struct Keychain {
	private let query: [String: Any]

	init(context: LAContext) {
		query = [
			kSecClass as String: kSecClassGenericPassword,
			kSecUseAuthenticationContext as String: context,
		]
	}

	func set(namespace: String, account: String, value: String, strict: Bool) -> Result<Bool, KeychainError> {
		guard let data = value.data(using: .utf8) else { return .failure(.setValueInvalid) }
		var query = self.query
		query[kSecAttrLabel as String] = namespace
		query[kSecAttrAccount as String] = account
		query[kSecValueData as String] = data

		var status = SecItemAdd(query as CFDictionary, nil)
		guard status != errSecSuccess else { return .success(true) }
		guard !strict && status == errSecDuplicateItem else { return .failure(.unhandled(status: status)) }
		query.removeValue(forKey: kSecValueData as String)
		let update = [kSecValueData as String: data]
		status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
		guard status == errSecSuccess else { return .failure(.unhandled(status: status)) }
		return .success(true)
	}

	func get(namespace: String, account: String) -> Result<String, KeychainError> {
		var query = self.query
		query[kSecAttrLabel as String] = namespace
		query[kSecAttrAccount as String] = account
		query[kSecMatchLimit as String] = kSecMatchLimitOne
		// query[kSecReturnAttributes as String] = true
		query[kSecReturnData as String] = true

		var result: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		guard status == errSecSuccess else {
			return .failure(.unhandled(status: status))
		}
		guard let data = result as? Data,
		      let value = String(data: data, encoding: .utf8)
		else {
			return .failure(.getValueInvalid)
		}
		return .success(value)
	}

	func delete(namespace: String, account: String, strict: Bool) -> Result<Bool, KeychainError> {
		var query = self.query
		query[kSecAttrLabel as String] = namespace
		query[kSecAttrAccount as String] = account
		query[kSecMatchLimit as String] = kSecMatchLimitOne

		let status = SecItemDelete(query as CFDictionary)
		guard status != errSecSuccess else { return .success(true) }
		guard !strict, status == errSecItemNotFound else { return .failure(.unhandled(status: status)) }
		return .success(true)
	}
}

// Helpers

enum InputType {
	case get
	case set(value: String)
	case delete
}

struct Action {
	let type: InputType
	let namespace: String
	let key: String
	let strict: Bool
	let verbose: Bool
}

func parse(args: [String]) -> Action? {
	let verb = args[safe: 0] ?? ""
	let namespace = args[safe: 1] ?? ""
	let key = args[safe: 2] ?? ""

	let type: InputType
	guard
		isValid(param: verb),
		isValid(param: namespace),
		isValid(param: key)
	else { return nil }

	if verb == "set" {
		guard
			let value = args[safe: 3],
			isValid(param: value)
		else { return nil }
		type = .set(value: value)
	} else if verb == "get" {
		type = .get
	} else if verb == "delete" {
		type = .delete
	} else {
		return nil
	}
	let strict = args.contains("--strict")
	let verbose = args.contains("--verbose")
	return Action(type: type, namespace: namespace, key: key, strict: strict, verbose: verbose)
}

func isValid(param: String) -> Bool {
	let trimmed = param.trimmingCharacters(in: .whitespacesAndNewlines)
	if trimmed.isEmpty || trimmed == "--strict" || trimmed == "--verbose" {
		return false
	}
	return true
}

func normalize<T>(result: Result<T, KeychainError>) -> Result<String, KeychainError> {
	switch result {
	case let .success(value):
		return .success(String(describing: value))
	case let .failure(error):
		return .failure(error)
	}
}

public extension Array {
	subscript(safe index: Int) -> Element? {
		return indices.contains(index) ? self[index] : nil
	}
}

func EXIT(stdout message: String) -> Never {
	print(message)
	exit(EXIT_SUCCESS)
}

func EXIT(stderr message: String) -> Never {
	fputs(message + "\n", stderr)
	exit(EXIT_FAILURE)
}

func EXIT(error: LAError, verbose: Bool) -> Never {
	let int = error.code.rawValue
	let int32 = Int32(truncatingIfNeeded: int)
	if verbose {
		let debugDescription = error.userInfo["NSDebugDescription"] ?? ""
		print("[LAError][\(int32)] \(debugDescription)")
	}
	EXIT(stderr: error.localizedDescription)
}

#!/usr/bin/env swift
import Foundation
import LocalAuthentication

// Setup Helpers

// let log = Log(name: nil)
signal(SIGINT, signalHandler)
signal(SIGQUIT, signalHandler)
signal(SIGHUP, signalHandler)
signal(SIGTERM, signalHandler)

// Configure Authentication

let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
let context = LAContext()
context.touchIDAuthenticationAllowableReuseDuration = LATouchIDAuthenticationMaximumAllowableReuseDuration

// Check Biometric Support

var contextError: NSError?
if !context.canEvaluatePolicy(policy, error: &contextError) {
	print(contextError?.debugDescription ?? "This system doesn't support biometric authentication.")
	exit(EXIT_FAILURE)
}

// Validate Script Input

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.count == 1, arguments.first == "--version" || arguments.first == "-v" {
	// package.json.version
	print("1.0.1")
	exit(EXIT_SUCCESS)
}

if arguments.isEmpty || (arguments.count == 1 && arguments.first == "-h" || arguments.first == "--help") {
	print(
		"""
		Usage:
		    get    <namespace> <key>
		    set    <namespace> <key> <value> [strict]
		    delete <namespace> <key> [strict]

		Arguments:
		    <namespace> A unique value used to prevent storage conflicts.
		    <key>       The key to operate on.
		    <value>     The value to store (only for 'set').
		    strict      Optional boolean flag (true/false). Defaults to false.
		                 - For 'set': If the key already exists, the command will fail.
		                 - For 'delete': If the key does not exist, the command will fail.

		Examples:
		    set    namespace key value
		    set    namespace key value true
		    get    namespace key
		    delete namespace key
		    delete namespace key true
		"""
	)
	exit(EXIT_SUCCESS)
}

guard let input = parse(args: arguments) else {
	print("Invalid arguments. Use -h or --help for usage information.")
	exit(EXIT_FAILURE)
}

// Perform Operation

let keychain = Keychain(context: context)
let result: Result<String, KeychainError> = await auth(
	context: context,
	policy: policy,
	reason: "access macOS Keychain"
) {
	switch input {
	case let .get(namespace, key):
		let output = keychain.get(namespace: namespace, account: key)
		return normalize(result: output)

	case let .set(namespace, key, value, strict):
		let output = keychain.set(namespace: namespace, account: key, value: value, strict: strict)
		return normalize(result: output)

	case let .delete(namespace, key, strict):
		let output = keychain.delete(namespace: namespace, account: key, strict: strict)
		return normalize(result: output)
	}
}

// Handle Result

if case let .success(value) = result {
	print(value)
	exit(EXIT_SUCCESS)
} else if case let .failure(error) = result {
	// log.write(error.description)
	print(error.localizedDescription)
	exit(EXIT_FAILURE)
}

// Utilities

struct Keychain {
	private let query: [String: Any]

	init(context: LAContext) {
		query = [
			kSecClass as String: kSecClassGenericPassword,
			kSecUseAuthenticationContext as String: context,
		]
	}

	func set(namespace: String, account: String, value: String, strict: Bool) -> Result<Bool, KeychainError> {
		guard let data = value.data(using: .utf8) else { return .failure(.setConvertValueToData) }
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
		return handle(get: result)
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

	private func handle(get single: CFTypeRef?) -> Result<String, KeychainError> {
		guard let data = single as? Data else {
			return .failure(.getConvertItemToData)
		}
		guard let value = String(data: data, encoding: .utf8) else {
			return .failure(.getConvertDataToString)
		}
		return .success(value)
	}

	private func handle(get multiple: CFTypeRef?, strict: Bool) -> Result<[String], KeychainError> {
		guard let data = multiple as? [Data] else {
			return .failure(.getConvertItemToData)
		}
		let values = data.compactMap { item in String(data: item, encoding: .utf8) }
		if strict, values.count > 1 {
			return .failure(.getMoreThanOneItem)
		}
		return .success(values)
	}
}

struct Log {
	private let file: FileHandle

	init(name: String?) {
		let scriptPath = CommandLine.arguments[0]
		let scriptURL = URL(fileURLWithPath: scriptPath)
		let scriptDir = scriptURL.deletingLastPathComponent()
		let logName = name ?? scriptURL.deletingPathExtension().lastPathComponent
		let logURL = scriptDir.appendingPathComponent("\(logName).log")

		// Create Log File
		let fileManager = FileManager.default
		if !fileManager.fileExists(atPath: logURL.path) {
			guard fileManager.createFile(atPath: logURL.path, contents: nil, attributes: nil) else {
				print("Error: Unable to create log file.")
				exit(EXIT_FAILURE)
			}
		}

		// Create File Handle
		guard let handle = FileHandle(forWritingAtPath: logURL.path) else {
			print("Error: Unable to create file handle.")
			exit(EXIT_FAILURE)
		}
		file = handle
	}

	func clear() {
		do {
			try file.truncate(atOffset: 0)
		} catch {
			print("Log Error: \(error.localizedDescription)")
		}
	}

	func write(_ message: String) {
		guard let data = message.data(using: .utf8) else {
			print("Log Error: Invalid data.")
			return
		}

		do {
			try file.seekToEnd()
			try file.write(contentsOf: data)
			try file.close()
		} catch {
			print("Log Error: \(error.localizedDescription)")
		}
	}
}

// Helpers

func auth<T>(context: LAContext, policy: LAPolicy, reason: String, run: @escaping () -> T) async -> T {
	do {
		let success = try await context.evaluatePolicy(policy, localizedReason: reason)
		guard !success else {
			return run()
		}
		print("Authentication Failed:", "Unknown reason.")
	} catch {
		print(error.localizedDescription)
	}
	exit(EXIT_FAILURE)
}

enum Input {
	case get(namespace: String, key: String)
	case set(namespace: String, key: String, value: String, strict: Bool)
	case delete(namespace: String, key: String, strict: Bool)
}

func parse(args: [String]) -> Input? {
	guard case 3 ... 5 = arguments.count else { return nil }
	let verb = args[safe: 0] ?? ""
	let namespace = args[safe: 1] ?? ""
	let key = args[safe: 2] ?? ""
	let fourth = args[safe: 3] ?? ""
	let fifth = args[safe: 4] ?? ""
	guard !verb.isEmpty, !namespace.isEmpty, !key.isEmpty else { return nil }
	if verb == "set" {
		guard !fourth.isEmpty, fifth.isEmpty || get(bool: fifth) != nil else { return nil }
		return .set(namespace: namespace, key: key, value: fourth, strict: fifth == "true")
	} else if verb == "get" {
		guard fourth.isEmpty, fifth.isEmpty else { return nil }
		return .get(namespace: namespace, key: key)
	} else if verb == "delete" {
		guard fourth.isEmpty || get(bool: fourth) != nil, fifth.isEmpty else { return nil }
		return .delete(namespace: namespace, key: key, strict: fourth == "true")
	}
	return nil
}

func get(bool text: String) -> Bool? {
	switch text.lowercased() {
	case "true", "yes", "1": true
	case "false", "no", "0": false
	default: nil
	}
}

func normalize<T>(result: Result<T, KeychainError>) -> Result<String, KeychainError> {
	switch result {
	case let .success(value):
		return .success(String(describing: value))
	case let .failure(error):
		return .failure(error)
	}
}

enum KeychainError: Error, LocalizedError, CustomStringConvertible {
	case unhandled(status: OSStatus)
	case getConvertItemToData
	case getConvertDataToString
	case setConvertValueToData
	case getMoreThanOneItem

	// print(error.localizedDescription)
	var errorDescription: String? {
		switch self {
		case let .unhandled(status):
			if let message = SecCopyErrorMessageString(status, nil) as String? {
				return message
			} else {
				return "An unexpected keychain error occurred. OSStatus: \(status.description)"
			}
		case .getConvertItemToData:
			return "The data retrieved from the keychain was not in the expected format."
		case .getConvertDataToString:
			return "The data retrieved from the keychain could not be converted to a string."
		case .getMoreThanOneItem:
			return "The keychain returned more than one item."
		case .setConvertValueToData:
			return "The provided value could not be converted to data."
		}
	}

	// print(error)
	var description: String {
		switch self {
		case let .unhandled(status):
			return "KeychainError.unhandled(\(status))"
		case .getConvertItemToData:
			return "KeychainError.getConvertItemToData"
		case .getConvertDataToString:
			return "KeychainError.getConvertDataToString"
		case .setConvertValueToData:
			return "KeychainError.setConvertValueToData"
		case .getMoreThanOneItem:
			return "KeychainError.getMoreThanOneItem"
		}
	}
}

public extension Array {
	subscript(safe index: Int) -> Element? {
		return indices.contains(index) ? self[index] : nil
	}
}

let signalHandler: @convention(c) (Int32) -> Void = { code in
	_ = switch code {
	case SIGINT: "Process Interrupted (SIGINT)"
	case SIGQUIT: "Process Quit (SIGQUIT)"
	case SIGHUP: "Terminal Closed (SIGHUP)"
	case SIGTERM: "Process Terminated (SIGTERM)"
	default: "Unknown Signal \(code)"
	}
	// log.write(message)
	exit(EXIT_FAILURE)
}

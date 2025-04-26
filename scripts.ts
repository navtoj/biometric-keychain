#!/usr/bin/env bun
import { $, stderr } from 'bun';
import packageJson from './package.json';

class PrePublishOnly {
	private constructor() {}
	static async run() {
		// steps must run in order?
		const steps = [
			this.#buildTypescript,
			this.#updateUsageText('src/usage.txt', 'README.md', '```'),
			this.#updateUsageText('src/usage.txt', 'src/main.swift', '"""'),
			this.#checkPackageVersion,
			() => this.#updateSwiftPackageVersion('src/main.swift'),
			this.#checkCleanGit,
			this.#runTests,
		] satisfies (() => Promise<String | void>)[];

		for await (const step of steps) {
			const result = await step();
			if (result) {
				console.error(result);
				process.exit(1);
			}
		}
	}

	static async #runTests() {
		const output = await $`bun test --bail`.nothrow();
		if (!output.stderr.toString().includes('0 fail'))
			return '\n❌ Some test(s) failed.';
	}

	static async #checkCleanGit() {
		const uncommitted = await $`git status --porcelain`.text();
		if (uncommitted) return '❌ Uncommitted changes detected.';
		const unpushed = await $`git log origin/main..HEAD`.text();
		if (unpushed) return '❌ Unpushed changes detected.';
	}

	static async #buildTypescript() {
		try {
			await $`bun run build`.text();
		} catch (error) {
			console.error(error);
			return '❌ Failed to build TypeScript.';
		}
	}

	static async #checkPackageVersion() {
		const remoteVersion =
			await $`npm view ${packageJson.name} version`.text();

		const localVersionParts = packageJson.version
			.split('.')
			.map(part => parseInt(part));
		const remoteVersionParts = remoteVersion
			.split('.')
			.map(part => parseInt(part));

		const isValidVersion =
			localVersionParts.length === 3 &&
			remoteVersionParts.length === 3 &&
			localVersionParts[0] >= remoteVersionParts[0] &&
			localVersionParts[1] >= remoteVersionParts[1] &&
			localVersionParts[2] > remoteVersionParts[2];
		if (!isValidVersion)
			return `❌ Invalid package.json version: ${packageJson.version}`;
	}

	static async #updateSwiftPackageVersion(swiftPath: string) {
		const identifier = '// package.json.version';
		const swiftFile = Bun.file(swiftPath);
		const swiftText = await swiftFile.text();
		const swiftLines = swiftText.split('\n');
		const versionLineIndex = swiftLines.findIndex(
			line => line.trim() === identifier,
		);
		const indentation =
			swiftLines.at(versionLineIndex)?.replace(identifier, '') ?? '';
		const versionLine = swiftLines.at(versionLineIndex + 1);
		if (!versionLine) return '❌ Failed to find version line.';
		if (versionLine.includes(packageJson.version)) return;
		const newVersionLine = `${indentation}SUCCESS(result: "${packageJson.version}")`;
		swiftLines[versionLineIndex + 1] = newVersionLine;
		const newSwiftText = swiftLines.join('\n');
		await Bun.write(swiftPath, newSwiftText);
	}

	static #updateUsageText(from: string, to: string, identifier: string) {
		return async () => {
			try {
				const updateFile = Bun.file(to);
				const updateText = await updateFile.text();

				const firstIndex =
					updateText.indexOf(identifier) + identifier.length;
				const indentation =
					updateText
						.split('\n')
						.find(line => {
							const trimmedLine = line.trim();
							return (
								trimmedLine.startsWith(identifier) &&
								trimmedLine.endsWith(identifier)
							);
						})
						?.replace(identifier, '') ?? '';
				const secondIndex = updateText.indexOf(identifier, firstIndex);

				const updateTextBefore = updateText.slice(0, firstIndex);
				const updateTextAfter = updateText.slice(secondIndex);

				const usageFile = Bun.file(from);
				const usageText = await usageFile.text();
				const safeUsageText = usageText
					.split('\n')
					.map(line =>
						line.trim() === '' ? line : indentation + line,
					)
					.join('\n')
					// .replaceAll(
					// 	'namespace',
					// 	Math.random().toString(36).substring(2, 22),
					// )
					.trim();

				const newUpdateText =
					updateTextBefore +
					'\n' +
					indentation +
					safeUsageText +
					'\n' +
					indentation +
					updateTextAfter;
				await Bun.write(to, newUpdateText);
			} catch (error) {
				console.error(error);
				return `❌ Failed to update ${to}`;
			}
		};
	}
}

// run the relevant script
const args = process.argv.slice(2);
switch (args.join(' ')) {
	case '--prepublishOnly':
		await PrePublishOnly.run();
		break;

	default:
		console.error(
			`Unknown command. Check the script at "${
				process.argv.at(1) ?? 'scripts.ts'
			}".`,
		);
		process.exit(1);
}

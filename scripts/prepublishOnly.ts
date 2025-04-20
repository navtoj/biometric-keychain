#!/usr/bin/env bun
import { $ } from 'bun';
import packageJson from '../package.json';

class Script {
	private constructor() {}
	static async run() {
		// remember : steps must run in order
		const steps = [
			this.updateUsageText('README.md', '```'),
			this.updateUsageText('src/main.swift', '"""'),
			this.checkPackageVersion,
			this.updateSwiftPackageVersion,
			this.checkCleanGit,
		] satisfies (() => Promise<String | void>)[];

		for await (const step of steps) {
			const result = await step();
			if (result) {
				console.error(result);
				process.exit(1);
			}
		}
	}

	static async checkCleanGit() {
		const output = await $`git status --porcelain`.text();
		if (output) return '❌ Uncommitted changes detected.';
	}

	static async checkPackageVersion() {
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

	static async updateSwiftPackageVersion() {
		const swiftPath = 'src/main.swift';
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
		const newVersionLine = `${indentation}print("${packageJson.version}")`;
		swiftLines[versionLineIndex + 1] = newVersionLine;
		const newSwiftText = swiftLines.join('\n');
		await Bun.write(swiftPath, newSwiftText);
	}

	static updateUsageText(path: string, identifier: string) {
		const usagePath = 'src/usage.txt';
		return async () => {
			try {
				const updateFile = Bun.file(path);
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

				const usageFile = Bun.file(usagePath);
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
				await Bun.write(path, newUpdateText);
			} catch (error) {
				console.error(error);
				return `❌ Failed to update ${path}`;
			}
		};
	}
}

await Script.run();

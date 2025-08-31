//
//  RemovePhpVersionCommand.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 21/03/2023.
//  Copyright © 2023 Nico Verbruggen. All rights reserved.
//

import Foundation

class RemovePhpVersionCommand: BrewCommand {
    let formula: String
    let version: String
    let phpGuard: PhpGuard

    init(formula: String) {
        self.version = formula
            .replacingOccurrences(of: "php@", with: "")
            .replacingOccurrences(of: "shivammathur/php/", with: "")
        self.formula = formula
        self.phpGuard = PhpGuard()
    }

    func getCommandTitle() -> String {
        return "phpman.steps.removing".localized("PHP \(version)...")
    }

    func execute(onProgress: @escaping (BrewCommandProgress) -> Void) async throws {
        onProgress(.create(
            value: 0.2,
            title: getCommandTitle(),
            description: "phpman.steps.wait".localized
        ))

        let command = """
            export HOMEBREW_DOWNLOAD_CONCURRENCY=auto; \
            export HOMEBREW_NO_INSTALL_UPGRADE=true; \
            export HOMEBREW_NO_INSTALL_CLEANUP=true; \
            \(Paths.brew) remove \(formula) --force --ignore-dependencies
            """

        do {
            try await BrewPermissionFixer().fixPermissions()
        } catch {
            return
        }

        var loggedMessages: [String] = []

        let (process, _) = try! await Shell.attach(
            command,
            didReceiveOutput: { text, _ in
                if !text.isEmpty {
                    Log.perf(text)
                    loggedMessages.append(text)
                }
            },
            withTimeout: .minutes(5)
        )

        if process.terminationStatus <= 0 {
            onProgress(.create(value: 0.95, title: getCommandTitle(), description: "phpman.steps.reloading".localized))

            await PhpEnvironments.detectPhpVersions()

            await MainMenu.shared.refreshActiveInstallation()

            if let version = phpGuard.currentVersion {
                await MainMenu.shared.switchToPhpVersionAndWait(version, silently: true)
            }

            onProgress(.create(value: 1, title: getCommandTitle(), description: "phpman.steps.success".localized))
        } else {
            throw BrewCommandError(error: "The command failed to run correctly.", log: loggedMessages)
        }
    }
}

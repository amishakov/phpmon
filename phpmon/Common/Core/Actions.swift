//
//  Services.swift
//  PHP Monitor
//
//  Copyright © 2023 Nico Verbruggen. All rights reserved.
//

import Foundation
import AppKit

class Actions {

    // MARK: - Services

    public static func restartPhpFpm() async {
        await brew("services restart \(Homebrew.Formulae.php.name)", sudo: Homebrew.Formulae.php.elevated)
    }

    public static func restartNginx() async {
        await brew("services restart \(Homebrew.Formulae.nginx.name)", sudo: Homebrew.Formulae.nginx.elevated)
    }

    public static func restartDnsMasq() async {
        await brew("services restart \(Homebrew.Formulae.dnsmasq.name)", sudo: Homebrew.Formulae.dnsmasq.elevated)
    }

    public static func stopValetServices() async {
        await brew("services stop \(Homebrew.Formulae.php.name)", sudo: Homebrew.Formulae.php.elevated)
        await brew("services stop \(Homebrew.Formulae.nginx.name)", sudo: Homebrew.Formulae.nginx.elevated)
        await brew("services stop \(Homebrew.Formulae.dnsmasq.name)", sudo: Homebrew.Formulae.dnsmasq.elevated)
    }

    public static func fixHomebrewPermissions() throws {
        var servicesCommands = [
            "\(Paths.brew) services stop \(Homebrew.Formulae.nginx)",
            "\(Paths.brew) services stop \(Homebrew.Formulae.dnsmasq)"
        ]

        var cellarCommands = [
            "chown -R \(Paths.whoami):admin \(Paths.cellarPath)/\(Homebrew.Formulae.nginx)",
            "chown -R \(Paths.whoami):admin \(Paths.cellarPath)/\(Homebrew.Formulae.dnsmasq)"
        ]

        PhpEnv.shared.availablePhpVersions.forEach { version in
            let formula = version == PhpEnv.brewPhpAlias
                ? "php"
                : "php@\(version)"
            servicesCommands.append("\(Paths.brew) services stop \(formula)")
            cellarCommands.append("chown -R \(Paths.whoami):admin \(Paths.cellarPath)/\(formula)")
        }

        let script =
            servicesCommands.joined(separator: " && ")
            + " && "
            + cellarCommands.joined(separator: " && ")

        let appleScript = NSAppleScript(
            source: "do shell script \"\(script)\" with administrator privileges"
        )

        let eventResult: NSAppleEventDescriptor? = appleScript?.executeAndReturnError(nil)

        if eventResult == nil {
            throw HomebrewPermissionError(kind: .applescriptNilError)
        }
    }

    // MARK: - Finding Config Files

    public static func openGenericPhpConfigFolder() {
        let files = [NSURL(fileURLWithPath: "\(Paths.etcPath)/php")]
        NSWorkspace.shared.activateFileViewerSelecting(files as [URL])
    }

    public static func openPhpConfigFolder(version: String) {
        let files = [NSURL(fileURLWithPath: "\(Paths.etcPath)/php/\(version)/php.ini")]
        NSWorkspace.shared.activateFileViewerSelecting(files as [URL])
    }

    public static func openGlobalComposerFolder() {
        let file = URL(string: "file://~/.composer/composer.json".replacingTildeWithHomeDirectory)!
        NSWorkspace.shared.activateFileViewerSelecting([file] as [URL])
    }

    public static func openValetConfigFolder() {
        let file = URL(string: "file://~/.config/valet".replacingTildeWithHomeDirectory)!
        NSWorkspace.shared.activateFileViewerSelecting([file] as [URL])
    }

    public static func openPhpMonitorConfigFile() {
        let file = URL(string: "file://~/.config/phpmon".replacingTildeWithHomeDirectory)!
        NSWorkspace.shared.activateFileViewerSelecting([file] as [URL])
    }

    // MARK: - Other Actions

    public static func createTempPhpInfoFile() async -> URL {
        try! FileSystem.writeAtomicallyToFile("/tmp/phpmon_phpinfo.php", content: "<?php phpinfo();")

        // Tell php-cgi to run the PHP and output as an .html file
        await Shell.quiet("\(Paths.binPath)/php-cgi -q /tmp/phpmon_phpinfo.php > /tmp/phpmon_phpinfo.html")

        return URL(string: "file:///private/tmp/phpmon_phpinfo.html")!
    }

    // MARK: - Fix My Valet

    /**
     Detects all currently available PHP versions,
     and unlinks each and every one of them.
     
     This all happens in sequence, nothing runs in parallel.
     
     After this, the brew services are also stopped,
     the latest PHP version is linked, and php + nginx are restarted.
     
     If this does not solve the issue, the user may need to install additional
     extensions and/or run `composer global update`.
     */
    public static func fixMyValet() async {
        await InternalSwitcher().performSwitch(to: PhpEnv.brewPhpAlias)
        await brew("services restart \(Homebrew.Formulae.dnsmasq)", sudo: Homebrew.Formulae.dnsmasq.elevated)
        await brew("services restart \(Homebrew.Formulae.php)", sudo: Homebrew.Formulae.php.elevated)
        await brew("services restart \(Homebrew.Formulae.nginx)", sudo: Homebrew.Formulae.nginx.elevated)
    }
}

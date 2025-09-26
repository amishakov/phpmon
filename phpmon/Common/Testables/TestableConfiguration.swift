//
//  TestableConfiguration.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 16/10/2022.
//  Copyright © 2023 Nico Verbruggen. All rights reserved.
//

import Foundation

public struct TestableConfiguration: Codable {
    var architecture: String
    var filesystem: [String: FakeFile]
    var shellOutput: [String: BatchFakeShellOutput]
    var commandOutput: [String: String]
    var preferenceOverrides: [PreferenceName: Bool]

    init(
        architecture: String,
        filesystem: [String: FakeFile],
        shellOutput: [String: BatchFakeShellOutput],
        commandOutput: [String: String],
        preferenceOverrides: [PreferenceName: Bool],
        phpVersions: [VersionNumber]
    ) {
        self.architecture = architecture
        self.filesystem = filesystem
        self.shellOutput = shellOutput
        self.commandOutput = commandOutput
        self.preferenceOverrides = preferenceOverrides

        phpVersions.enumerated().forEach { (index, version) in
            self.addPhpVersion(version, primary: index == 0)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case architecture, filesystem, shellOutput, commandOutput, preferenceOverrides
    }

    // MARK: Add PHP versions

    private var primaryPhpVersion: VersionNumber?
    private var secondaryPhpVersions: [VersionNumber] = []

    // swiftlint:disable function_body_length
    mutating func addPhpVersion(_ version: VersionNumber, primary: Bool) {
        if primary {
            if primaryPhpVersion != nil {
                fatalError("You cannot add multiple primary PHP versions to a testable configuration!")
            }
            primaryPhpVersion = version
        } else {
            self.secondaryPhpVersions.append(version)
        }

        self.filesystem = self.filesystem.merging([
            "/opt/homebrew/opt/php@\(version.short)/bin/php"
                : .fake(.symlink, "/opt/homebrew/Cellar/php/\(version.long)/bin/php"),
            "/opt/homebrew/opt/php@\(version.short)/bin/php-config"
                : .fake(.symlink, "/opt/homebrew/Cellar/php/\(version.long)/bin/php-config"),
            "/opt/homebrew/Cellar/php/\(version.long)/bin/php"
                : .fake(.binary),
            "/opt/homebrew/Cellar/php/\(version.long)/bin/php-config"
                : .fake(.binary),
            "/opt/homebrew/etc/php/\(version.short)/php-fpm.d/www.conf"
                : .fake(.text),
            "/opt/homebrew/etc/php/\(version.short)/php-fpm.d/valet-fpm.conf"
                : .fake(.text),
            "/opt/homebrew/etc/php/\(version.short)/php.ini"
                : .fake(.text),
            "/opt/homebrew/etc/php/\(version.short)/conf.d/php-memory-limits.ini"
                : .fake(.text)
        ]) { (_, new) in new }

        // PHP configuration files
        self.shellOutput["/opt/homebrew/opt/php@\(version.short)/bin/php --ini | grep -E -o '(/[^ ]+\\.ini)'"] =
            .instant("/opt/homebrew/etc/php/\(version.short)/conf.d/php-memory-limits.ini")

        // PHP Homebrew operations
        self.shellOutput["/opt/homebrew/bin/brew unlink php@\(version.short)"] = .delayed(0.2, "OK")
        self.shellOutput["sudo /opt/homebrew/bin/brew services stop php@\(version.short)"] = .delayed(0.2, "OK")
        self.shellOutput["sudo /opt/homebrew/bin/brew services start php@\(version.short)"] = .delayed(0.2, "OK")
        self.shellOutput["/opt/homebrew/bin/brew link php@\(version.short) --overwrite --force"] = .delayed(0.2, "OK")

        // PHP version output
        self.commandOutput["/opt/homebrew/opt/php@\(version.short)/bin/php-config --version"] = version.long
        self.commandOutput["/opt/homebrew/opt/php@\(version.short)/bin/php -v"] = "OK"

        if primary {
            // Files expected to be present for currently linked PHP version
            self.shellOutput["ls /opt/homebrew/opt | grep php"] =
                .instant("php")
            self.shellOutput["/opt/homebrew/bin/php --ini | grep -E -o '(/[^ ]+\\.ini)'"] =
                .instant("/opt/homebrew/etc/php/\(version.short)/conf.d/php-memory-limits.ini")
            self.filesystem["/opt/homebrew/opt/php"]
                = .fake(.symlink, "/opt/homebrew/Cellar/php/\(version.long)")
            self.filesystem["/opt/homebrew/opt/php/bin/php"]
                = .fake(.symlink, "/opt/homebrew/Cellar/php/\(version.long)/bin/php")
            self.filesystem["/opt/homebrew/bin/php"]
                = .fake(.symlink, "/opt/homebrew/Cellar/php/\(version.long)/bin/php")
            self.filesystem["/opt/homebrew/bin/php-config"]
                = .fake(.symlink, "/opt/homebrew/Cellar/php/\(version.short)/bin/php-config")
            self.commandOutput["/opt/homebrew/bin/php-config --version"]
                = version.long
        } else {
            // Output expected to be present for non-linked PHP versions
            self.shellOutput["ls /opt/homebrew/opt | grep php@"] =
                BatchFakeShellOutput.instant(
                    self.secondaryPhpVersions
                        .map { "php@\($0.short)" }
                        .joined(separator: "\n")
                )
        }
    }
    // swiftlint:enable function_body_length

    // MARK: Interactions

    func apply() {
        Log.separator()
        Log.info("USING TESTABLE CONFIGURATION...")
        Log.separator()
        Log.info("Applying fake shell...")
        ActiveShell.useTestable(shellOutput)
        Log.info("Applying fake filesystem...")
        ActiveFileSystem.useTestable(filesystem)
        Log.info("Applying fake commands...")
        ActiveCommand.useTestable(commandOutput)
        Log.info("Applying temporary preference overrides...")
        preferenceOverrides.forEach { (key: PreferenceName, value: Any?) in
            Preferences.shared.cachedPreferences[key] = value
        }

        if Valet.shared.installed {
            Log.info("Applying fake scanner...")
            ValetScanner.useFake()
            Log.info("Applying fake services manager...")
            ServicesManager.useFake()
            Log.info("Applying fake Valet domain interactor...")
            ValetInteractor.useFake()
        }

        // Clear volatile app state for tests
        UserDefaults.standard.removeObject(forKey: PersistentAppState.lastAutomaticUpdateCheck.rawValue)

        // Set variable to tell app we're testin'
        App.hasLoadedTestableConfiguration = true
    }

    // MARK: Persist and load

    func toJson(pretty: Bool = false) -> String {
        let data = try! JSONEncoder().encode(self)

        if pretty {
            return data.prettyPrintedJSONString! as String
        }

        return String(data: data, encoding: .utf8)!
    }

    static func loadFrom(path: String) -> TestableConfiguration {
        let url = URL(fileURLWithPath: path.replacingTildeWithHomeDirectory)

        if !FileManager.default.fileExists(atPath: url.path) {
            /*
             You will need to run the `TestableConfigurationTest` test,
             which will generate two configuration files you can use.
             */
            fatalError("Error: the expected configuration file at \(url.path) is missing!")
        }

        /*
         If the decoder below fails to decode the configuration file,
         the configuration may have been updated.
         In that case, you will need to run the test (see above) again.
         */
        return try! JSONDecoder().decode(
            TestableConfiguration.self,
            from: try! String(contentsOf: url, encoding: .utf8).data(using: .utf8)!
        )
    }
}

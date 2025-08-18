//
//  MainMenu+Startup.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 03/01/2022.
//  Copyright © 2023 Nico Verbruggen. All rights reserved.
//

import Cocoa
import NVAlert

extension MainMenu {
    /**
     Kick off the startup of the rendering of the main menu.
     */
    func startup() async {
        // Start with the icon
        Task { @MainActor in
            self.setStatusBar(image: NSImage.statusBarIcon)
        }

        if await Startup().checkEnvironment() {
            await self.onEnvironmentPass()
        } else {
            await self.onEnvironmentFail()
        }
    }

    /**
     When the environment is all clear and the app can run, let's go.
     */
    private func onEnvironmentPass() async {
        // Determine what the `php` formula is aliased to
        await PhpEnvironments.shared.determinePhpAlias()

        // Make sure that broken symlinks are removed ASAP
        await BrewDiagnostics.checkForOutdatedPhpInstallationSymlinks()

        // Initialize preferences
        _ = Preferences.shared

        // Put some useful diagnostics information in log
        BrewDiagnostics.logBootInformation()

        // Attempt to find out more info about Valet
        if Valet.shared.version != nil {
            Log.info("PHP Monitor has extracted the version number of Valet: \(Valet.shared.version!.text)")

            // Validate the version (this will enforce which versions of PHP are supported)
            Valet.shared.validateVersion()
        }

        // Validate the Homebrew version (determines install/upgrade functionality)
        await Brew.shared.determineVersion()

        // Actually detect the PHP versions
        await PhpEnvironments.detectPhpVersions()

        // Verify third party taps
        // The missing tap(s) will be actionable later
        await BrewDiagnostics.verifyThirdPartyTaps()

        // Check for an alias conflict
        await BrewDiagnostics.checkForCaskConflict()

        // Attempt to find out if PHP-FPM is broken
        PhpEnvironments.prepare()

        // Set up the filesystem watcher for the Homebrew binaries
        App.shared.prepareHomebrewWatchers()

        // Check for other problems
        WarningManager.shared.evaluateWarnings()

        // Set up the config watchers on launch (updated automatically when switching)
        App.shared.handlePhpConfigWatcher()

        // Detect built-in and custom applications
        await detectApplications()

        // Load the rollback preset
        PresetHelper.loadRollbackPresetFromFile()

        // Load the global hotkey
        App.shared.loadGlobalHotkey()

        // Set up menu items
        AppDelegate.instance.configureMenuItems(standalone: !Valet.installed)

        if Valet.installed {
            // Preload all sites
            await Valet.shared.startPreloadingSites()

            // After preloading sites, check for PHP-FPM pool conflicts
            await BrewDiagnostics.checkForValetMisconfiguration()

            // Check if PHP-FPM is broken (should be fixed automatically if phpmon >= 6.0)
            await Valet.shared.notifyAboutBrokenPhpFpm()

            // A non-default TLD is not officially supported since Valet 3.2.x
            Valet.shared.notifyAboutUnsupportedTLD()
        }

        // Keep track of which PHP versions are currently about to release
        Log.info("Experimental PHP versions are: \(Constants.ExperimentalPhpVersions)")

        // Find out which services are active
        Log.info("The services manager knows about \(ServicesManager.shared.services.count) services.")

        // We are ready!
        PhpEnvironments.shared.isBusy = false

        // Finally!
        Log.info("PHP Monitor is ready to serve!")

        // Avoid showing the "startup timeout" alert
        Startup.invalidateTimeoutTimer()

        // Check if we upgraded from a previous version
        AppUpdater.checkIfUpdateWasPerformed()

        // Post-launch stats and update check, but only if not running tests
        await performPostLaunchActions()
    }

    /**
     Performs a set of post-launch actions, like incrementing stats and checking for updates.
     (This code is skipped when running SwiftUI previews.)
     */
    private func performPostLaunchActions() async {
        if isRunningSwiftUIPreview {
            return
        }

        Stats.incrementSuccessfulLaunchCount()
        Stats.evaluateSponsorMessageShouldBeDisplayed()

        if Stats.successfulLaunchCount == 1 {
            Log.info("Should present the first launch screen!")
            Task { @MainActor in
                OnboardingWindowController.show()
            }
        } else {
            // Check for updates
            await AppUpdater().checkForUpdates(userInitiated: false)

            // Check if the linked version has changed between launches of phpmon
            await PhpGuard().compareToLastGlobalVersion()
        }
    }

    /**
     When the environment is not OK, present an alert to inform the user.
     */
    private func onEnvironmentFail() async {
        Task { @MainActor [self] in
            NVAlert()
                .withInformation(
                    title: "alert.cannot_start.title".localized,
                    subtitle: "alert.cannot_start.subtitle".localized,
                    description: "alert.cannot_start.description".localized
                )
                .withPrimary(text: "alert.cannot_start.retry".localized)
                .withSecondary(text: "alert.cannot_start.close".localized, action: { vc in
                    vc.close(with: .alertSecondButtonReturn)
                    exit(1)
                })
                .show()

            Task { // An issue occurred, fire startup checks again after dismissal
                await startup()
            }
        }
    }

    /**
     Detect which applications are installed that can be used to open a domain's source directory.
     */
    private func detectApplications() async {
        Log.info("Detecting applications...")

        App.shared.detectedApplications = await Application.detectPresetApplications()

        let customApps = Preferences.custom.scanApps?.map { appName in
            return Application(appName, .user_supplied)
        } ?? []

        var detectedCustomApps: [Application] = []

        for app in customApps where await app.isInstalled() {
            detectedCustomApps.append(app)
        }

        App.shared.detectedApplications
            .append(contentsOf: detectedCustomApps)

        let appNames = App.shared.detectedApplications.map { app in
            return app.name
        }

        Log.info("Detected applications: \(appNames)")
    }
}

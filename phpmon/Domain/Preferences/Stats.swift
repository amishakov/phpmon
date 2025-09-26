//
//  Stats.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 29/01/2022.
//  Copyright © 2023 Nico Verbruggen. All rights reserved.
//

import Foundation
import Cocoa
import NVAlert

class Stats {

    /**
     Keep track of how many times the app has been successfully launched.
     
     This is used to determine whether it is time to show the sponsor
     encouragement alert, but I'd like to include this stat somewhere
     else as well.
     */
    public static var successfulLaunchCount: Int {
        UserDefaults.standard.integer(
            forKey: InternalStats.launchCount.rawValue
        )
    }

    /**
     Keep track of how many times the app has successfully switched
     between different PHP versions.
     
     This is used to determine whether it is time to show the sponsor
     encouragement alert, but I'd like to include this stat somewhere
     else as well.
     */
    public static var successfulSwitchCount: Int {
        UserDefaults.standard.integer(
            forKey: InternalStats.switchCount.rawValue
        )
    }

    /**
     Did the user see the sponsor encouragement / thank you message?
     Annoying the user is the worst, so let's not show the message twice.
     */
    public static var didSeeSponsorEncouragement: Bool {
        UserDefaults.standard.bool(
            forKey: InternalStats.didSeeSponsorEncouragement.rawValue
        )
    }

    public static var lastGlobalPhpVersion: String {
        UserDefaults.standard.string(forKey: InternalStats.lastGlobalPhpVersion.rawValue) ?? ""
    }

    /**
     Increment the successful launch count. This should only be
     called when the user has not encountered ANY issues starting
     up the application.
     */
    public static func incrementSuccessfulLaunchCount() {
        UserDefaults.standard.set(
            Stats.successfulLaunchCount + 1,
            forKey: InternalStats.launchCount.rawValue
        )
    }

    /**
     Increment the successful switch count.
     */
    public static func incrementSuccessfulSwitchCount() {
        UserDefaults.standard.set(
            Stats.successfulSwitchCount + 1,
            forKey: InternalStats.switchCount.rawValue
        )
    }

    /**
     Persist which PHP version was active when you last used the app.
     */
    public static func persistCurrentGlobalPhpVersion(version: String) {
        UserDefaults.standard.set(
            version,
            forKey: InternalStats.lastGlobalPhpVersion.rawValue
        )
    }

    public static func clearCurrentGlobalPhpVersion() {
        UserDefaults.standard.removeObject(forKey: InternalStats.lastGlobalPhpVersion.rawValue)
    }

    /**
     Determine if the sponsor message should be displayed.
     
     The rationale behind this is simple, some of the stats
     increasing beyond a certain point indicate the app
     is being used.
     
     We evaluate, first:
     - Successful version switches
     OR
     - Successful starts of the application
     
     AND, of course, you must never have seen the alert before.
     (see `didSeeSponsorEncouragement`)
     */
    public static func evaluateSponsorMessageShouldBeDisplayed() {

        if Shell is TestableShell {
            return Log.info("A fake shell is in use, skipping sponsor alert.")
        }

        if App.identifier.contains(".eap") {
            return Log.info("Sponsor messages never apply to beta builds.")
        }

        if Stats.didSeeSponsorEncouragement {
            return Log.info("Awesome, the user has already seen the sponsor message.")
        }

        if Stats.successfulLaunchCount < 7 && Stats.successfulSwitchCount < 40 {
            return Log.info("It is too soon to see the sponsor message (launched \(Stats.successfulLaunchCount) " +
                            "times, switched \(Stats.successfulSwitchCount) times).")
        }

        Task { @MainActor in
            let donate = NVAlert()
                .withInformation(
                    title: "startup.sponsor_encouragement.title".localized,
                    subtitle: "startup.sponsor_encouragement.subtitle".localized,
                    description: "startup.sponsor_encouragement.desc".localized
                )
                .withPrimary(text: "startup.sponsor_encouragement.accept".localized)
                .withSecondary(text: "startup.sponsor_encouragement.skip".localized)
                .withTertiary(text: "", action: { vc in
                    vc.close(with: .alertThirdButtonReturn)
                    NSWorkspace.shared.open(Constants.Urls.DonationPage)
                }).didSelectPrimary()

            if donate {
                Log.info("The user is an absolute badass for choosing this option. Thank you.")
                NSWorkspace.shared.open(Constants.Urls.DonationPayment)
            }

            UserDefaults.standard.set(true, forKey: InternalStats.didSeeSponsorEncouragement.rawValue)
        }
    }
}

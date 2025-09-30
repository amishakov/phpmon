//
//  StartupTest.swift
//  UI Tests
//
//  Created by Nico Verbruggen on 14/10/2022.
//  Copyright © 2023 Nico Verbruggen. All rights reserved.
//

import XCTest

final class StartupTest: UITestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {}

    final func test_launch_halts_due_to_system_configuration_issue() throws {
        var configuration = TestableConfigurations.working
        configuration.filesystem["/opt/homebrew/bin/php"] = nil // PHP binary must be missing

        let app = launch(with: configuration)

        // Dialog 1: "PHP is not correctly installed"
        assertAllExist([
            app.dialogs["generic.notice".localized],
            app.staticTexts["startup.errors.php_binary.title".localized],
            app.buttons["generic.ok".localized]
        ])
        click(app.buttons["generic.ok".localized])

        // Dialog 2: PHP Monitor failed to start
        assertAllExist([
            app.dialogs["generic.notice".localized],
            app.staticTexts["alert.cannot_start.title".localized],
            app.buttons["alert.cannot_start.retry".localized],
            app.buttons["alert.cannot_start.close".localized]
        ])
        click(app.buttons["alert.cannot_start.retry".localized])

        // Dialog 1 again
        assertExists(app.staticTexts["startup.errors.php_binary.title".localized])

        // At this point, we can terminate the test
        app.terminate()
    }

    final func test_get_warning_about_missing_fpm_symlink() throws {
        var configuration = TestableConfigurations.working
        configuration.filesystem["/opt/homebrew/etc/php/8.4/php-fpm.d/valet-fpm.conf"] = nil

        let app = launch(with: configuration)

        assertExists(app.staticTexts["alert.php_fpm_broken.title".localized], 3.0)
        click(app.buttons["generic.ok".localized])
    }

    final func test_get_warning_about_unsupported_valet_version() throws {
        var configuration = TestableConfigurations.working
        configuration.shellOutput["valet --version"] = .instant("Laravel Valet 5.0")

        let app = launch(with: configuration)

        assertExists(app.staticTexts["startup.errors.valet_version_not_supported.title".localized], 3.0)
        click(app.buttons["generic.ok".localized])
    }
}

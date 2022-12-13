//
//  DomainListVC+Actions.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 23/12/2021.
//  Copyright © 2022 Nico Verbruggen. All rights reserved.
//

import Foundation
import Cocoa

extension DomainListVC {

    @objc func openInBrowser() {
        guard let selected = self.selected else {
            return
        }

        guard let url = selected.getListableUrl() else {
            BetterAlert()
                .withInformation(
                    title: "domain_list.alert.invalid_folder_name".localized,
                    subtitle: "domain_list.alert.invalid_folder_name_desc".localized
                )
                .withPrimary(text: "OK")
                .show()
            return
        }

        NSWorkspace.shared.open(url)
    }

    @objc func openInFinder() async {
        await Shell.quiet("open '\(selectedSite!.absolutePath)'")
    }

    @objc func openInTerminal() async {
        await Shell.quiet("open -b com.apple.terminal '\(selectedSite!.absolutePath)'")
    }

    @objc func openWithEditor(sender: EditorMenuItem) async {
        guard let editor = sender.editor else { return }
        await editor.openDirectory(file: selectedSite!.absolutePath)
    }

    // MARK: - UI interaction

    private func performAction(command: String, beforeCellReload: @escaping () -> Void) {
        let rowToReload = tableView.selectedRow

        waitAndExecute {
            await Shell.quiet(command)
        } completion: { [self] in
            beforeCellReload()
            tableView.reloadData(forRowIndexes: [rowToReload], columnIndexes: [0, 1, 2, 3, 4])
            tableView.deselectRow(rowToReload)
            tableView.selectRowIndexes([rowToReload], byExtendingSelection: true)
        }
    }

    private func reloadSelectedRow() {
        tableView.reloadData(forRowIndexes: [tableView.selectedRow], columnIndexes: [0, 1, 2, 3, 4])
        tableView.deselectRow(tableView.selectedRow)
        tableView.selectRowIndexes([tableView.selectedRow], byExtendingSelection: true)
    }

    // MARK: - Interactions with `valet` or terminal

    @objc func toggleSecure() {
        if selected is ValetSite {
            Task { await toggleSecureForSite() }
        } else {
            Task { await toggleSecureForProxy() }
        }
    }

    func toggleSecureForProxy() async {
        guard let proxy = selectedProxy else { return }

        do {
            // Recreate proxy as secure or unsecured proxy
            try await proxy.toggleSecure()
            // Send a notification about the new status (if applicable)
            self.notifyAboutModifiedSecureStatus(domain: proxy.domain, secured: proxy.secured)
            // Reload the UI (do this last so we don't invalidate the proxy)
            self.reloadSelectedRow()
        } catch {
            // Notify the user about a failed command
            let error = error as! ValetInteractionError
            self.notifyAboutFailedSecureStatus(command: error.command)
        }
    }

    func toggleSecureForSite() async {
        guard let site = selectedSite else { return }

        do {
            // Instruct Valet to secure or unsecure a site
            try await site.toggleSecure()
            // Send a notification about the new status (if applicable)
            self.notifyAboutModifiedSecureStatus(domain: site.name, secured: site.secured)
            // Reload the UI (do this last so we don't invalidate the proxy)
            self.reloadSelectedRow()
        } catch {
            // Notify the user about a failed command
            let error = error as! ValetInteractionError
            self.notifyAboutFailedSecureStatus(command: error.command)
        }
    }

    #warning("ValetInteractor needs to be used here instead of directly issuing commands to valet")
    @objc func isolateSite(sender: PhpMenuItem) {
        let command = "sudo \(Paths.valet) isolate php@\(sender.version) --site '\(self.selectedSite!.name)' && exit;"

        self.performAction(command: command) {
            self.selectedSite!.determineIsolated()
            self.selectedSite!.determineComposerPhpVersion()

            if self.selectedSite!.isolatedPhpVersion == nil {
                BetterAlert()
                    .withInformation(
                        title: "domain_list.alerts_isolation_failed.title".localized,
                        subtitle: "domain_list.alerts_isolation_failed.subtitle".localized,
                        description: "domain_list.alerts_isolation_failed.desc".localized(command)
                    )
                    .withPrimary(text: "OK")
                    .show()
            }
        }
    }

    #warning("ValetInteractor needs to be used here instead of directly issuing commands to valet")
    @objc func removeIsolatedSite() {
        self.performAction(command: "sudo \(Paths.valet) unisolate --site '\(self.selectedSite!.name)' && exit;") {
            self.selectedSite!.isolatedPhpVersion = nil
            self.selectedSite!.determineComposerPhpVersion()
        }
    }

    @objc func unlinkSite() {
        guard let site = selectedSite else {
            return
        }

        if site.aliasPath == nil {
            return
        }

        Alert.confirm(
            onWindow: view.window!,
            messageText: "domain_list.confirm_unlink".localized(site.name),
            informativeText: "domain_list.confirm_unlink_desc".localized,
            buttonTitle: "domain_list.unlink".localized,
            secondButtonTitle: "Cancel",
            style: .critical,
            onFirstButtonPressed: {
                self.waitAndExecute {
                    Task { await site.unlink() }
                } completion: {
                    Task { await self.reloadDomains() }
                }
            }
        )
    }

    @objc func removeProxy() {
        guard let proxy = selectedProxy else {
            return
        }

        Alert.confirm(
            onWindow: view.window!,
            messageText: "domain_list.confirm_unproxy".localized("\(proxy.domain).\(proxy.tld)"),
            informativeText: "domain_list.confirm_unproxy_desc".localized,
            buttonTitle: "domain_list.unproxy".localized,
            secondButtonTitle: "Cancel",
            style: .critical,
            onFirstButtonPressed: {
                self.waitAndExecute {
                    Task { await proxy.remove() }
                } completion: {
                    Task { await self.reloadDomains() }
                }
            }
        )
    }

    // MARK: - Alerts & Modals

    private func notifyAboutModifiedSecureStatus(domain: String, secured: Bool) {
        LocalNotification.send(
            title: "domain_list.alerts_status_changed.title".localized,
            subtitle: "domain_list.alerts_status_changed.desc"
                .localized(
                    // 1. The domain that was secured is listed
                    "\(domain).\(Valet.shared.config.tld)",
                    // 2. What the domain is is listed (secure / unsecure)
                    secured
                    ? "domain_list.alerts_status_secure".localized
                    : "domain_list.alerts_status_unsecure".localized
                ),
            preference: .notifyAboutSecureToggle
        )
    }

    private func notifyAboutFailedSecureStatus(command: String) {
        BetterAlert()
            .withInformation(
                title: "domain_list.alerts_status_not_changed.title".localized,
                subtitle: "domain_list.alerts_status_not_changed.desc".localized(command)
            )
            .withPrimary(text: "OK")
            .show()
    }
}

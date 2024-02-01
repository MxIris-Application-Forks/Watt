//
//  WorkspaceViewController.swift
//  Watt
//
//  Created by David Albert on 1/4/24.
//

import Cocoa
import SwiftUI

class WorkspaceViewController: NSSplitViewController {
    @ViewLoading var workspaceBrowserViewController: WorkspaceBrowserViewController
    @ViewLoading var textViewController: TextViewController

    var sidebarObserver: NSKeyValueObservation?

    var buffer: Buffer
    var workspace: Workspace? {
        didSet {
            workspaceBrowserViewController.workspace = workspace
        }
    }

    init(buffer: Buffer) {
        self.buffer = buffer
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        buffer = Buffer()
        super.init(coder: coder)
    }

    override func loadView() {
        super.loadView()
        workspaceBrowserViewController = WorkspaceBrowserViewController(workspace: workspace)
        textViewController = TextViewController(buffer)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        workspaceBrowserViewController.workspace = workspace

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: workspaceBrowserViewController)
        sidebarItem.isSpringLoaded = false

        let textItem = NSSplitViewItem(viewController: textViewController)

        workspaceBrowserViewController.view.frame.size.width = 250

        sidebarObserver = sidebarItem.observe(\.isCollapsed) { [weak self] item, _ in
            if item.isCollapsed {
                self?.view.window?.titlebarSeparatorStyle = .automatic
            } else {
                self?.view.window?.titlebarSeparatorStyle = .line
            }
        }

        addSplitViewItem(sidebarItem)
        addSplitViewItem(textItem)
    }

    override func viewWillAppear() {
        view.window?.initialFirstResponder = textViewController.view
    }

    @objc func openWorkspace(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: view.window!) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else {
                return
            }

            do {
                self.workspace = try Workspace(url: url)
            } catch {
                presentErrorAsSheetWithFallback(error)
            }
        }
    }
}

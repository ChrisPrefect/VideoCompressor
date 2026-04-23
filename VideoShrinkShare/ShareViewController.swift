import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// UIViewController-Host für die SwiftUI-basierte Share-Extension-UI.
/// iOS startet eine Subklasse von `UIViewController` als Entry-Point der
/// Share-Extension; wir hosten unsere SwiftUI-View darin.
final class ShareViewController: UIViewController {

    private var hostingController: UIHostingController<ShareExtensionMainView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let viewModel = ShareExtensionViewModel(
            extensionContext: extensionContext,
            inputItems: extensionContext?.inputItems as? [NSExtensionItem] ?? []
        )
        let root = ShareExtensionMainView(viewModel: viewModel)
        let host = UIHostingController(rootView: root)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
        self.hostingController = host
    }
}

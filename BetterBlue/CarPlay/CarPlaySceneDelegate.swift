//
//  CarPlaySceneDelegate.swift
//  BetterBlue
//

import CarPlay
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var controller: CarPlayController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        let controller = CarPlayController(interfaceController: interfaceController)
        controller.connect()
        self.controller = controller
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        controller?.disconnect()
        controller = nil
    }
}

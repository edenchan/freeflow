import AppKit
import SwiftUI

/// Menu-style provider preset picker. Hidden while only one preset is registered.
struct ProviderPicker: View {
    @Binding var selectionID: String

    var body: some View {
        if ProviderRegistry.all.count > 1 {
            HStack(spacing: 8) {
                Text("Provider")
                ProviderPopUp(selectionID: $selectionID)
                    .frame(minWidth: 168)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("API Provider")
            .accessibilityValue(currentTitle)
        }
    }

    private var currentTitle: String {
        ProviderRegistry.provider(id: selectionID)?.displayName ?? selectionID
    }
}

private struct ProviderPopUp: NSViewRepresentable {
    @Binding var selectionID: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selectionID: $selectionID)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.autoenablesItems = false
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rebuildMenu(on: button)
        select(selectionID, on: button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selectionID = $selectionID
        rebuildMenu(on: button)
        select(selectionID, on: button)
    }

    private func rebuildMenu(on button: NSPopUpButton) {
        guard let menu = button.menu else { return }
        let providers = ProviderRegistry.all
        if menu.items.count == providers.count,
           zip(menu.items, providers).allSatisfy({ $0.title == $1.displayName }) {
            return
        }
        menu.removeAllItems()
        for (index, provider) in providers.enumerated() {
            let item = NSMenuItem(title: provider.displayName, action: nil, keyEquivalent: "")
            item.tag = index
            item.representedObject = provider.id
            if let iconName = provider.iconResourceName,
               let base = Bundle.main.image(forResource: iconName) ?? NSImage(named: iconName) {
                let icon = base.copy() as? NSImage ?? base
                icon.isTemplate = true
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }
    }

    private func select(_ id: String, on button: NSPopUpButton) {
        let index = ProviderRegistry.all.firstIndex(where: { $0.id == id }) ?? 0
        if button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
    }

    final class Coordinator: NSObject {
        var selectionID: Binding<String>

        init(selectionID: Binding<String>) {
            self.selectionID = selectionID
        }

        @objc func changed(_ sender: NSPopUpButton) {
            guard let id = sender.selectedItem?.representedObject as? String else { return }
            selectionID.wrappedValue = id
        }
    }
}

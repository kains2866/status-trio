struct OutputDeviceListModel: Equatable {
    let orderedDevices: [AudioOutputDevice]
    let visibleDevices: [AudioOutputDevice]
    let canToggleExpansion: Bool

    static func make(
        devices: [AudioOutputDevice],
        order: [String],
        limit: Int?,
        isExpanded: Bool
    ) -> OutputDeviceListModel {
        let orderedDevices = OutputDeviceListPresentation.orderedDevices(
            devices,
            using: order
        )
        return OutputDeviceListModel(
            orderedDevices: orderedDevices,
            visibleDevices: OutputDeviceListPresentation.visibleDevices(
                from: orderedDevices,
                limit: limit,
                isExpanded: isExpanded
            ),
            canToggleExpansion: OutputDeviceListPresentation.canToggleExpansion(
                for: orderedDevices,
                limit: limit
            )
        )
    }
}

enum OutputDeviceListPresentation {
    static func orderedDevices(
        _ devices: [AudioOutputDevice],
        using order: [String]
    ) -> [AudioOutputDevice] {
        AudioDeviceOrder.ordered(devices, using: order, uid: \.uid)
    }

    /// The status-panel list. A hidden device still appears while it is the
    /// active output, so the list never loses its selected row.
    static func panelDevices(
        _ devices: [AudioOutputDevice],
        order: [String],
        hiddenUIDs: Set<String>
    ) -> [AudioOutputDevice] {
        orderedDevices(devices, using: order)
            .filter { $0.isCurrent || !isHidden($0, in: hiddenUIDs) }
    }

    static func isHidden(_ device: AudioOutputDevice, in hiddenUIDs: Set<String>) -> Bool {
        AudioDeviceOrder.isHidden(uid: device.uid, in: hiddenUIDs)
    }

    static func visibleDevices(
        from rows: [PanelAudioDeviceRow],
        limit: Int?,
        isExpanded: Bool
    ) -> [PanelAudioDeviceRow] {
        guard !isExpanded, let limit else { return rows }
        let count = max(0, limit)
        var visible = Array(rows.prefix(count))
        if let selected = rows.first(where: \.selected), !visible.contains(where: { $0.key == selected.key }) {
            if !visible.isEmpty { visible.removeLast() }
            visible.append(selected)
        }
        return visible
    }

    static func overflowRows(from rows: [PanelAudioDeviceRow], limit: Int?) -> [PanelAudioDeviceRow] {
        let visible = Set(visibleDevices(from: rows, limit: limit, isExpanded: false).map(\.key))
        return rows.filter { !visible.contains($0.key) }
    }

    static func canToggleExpansion(for rows: [PanelAudioDeviceRow], limit: Int?) -> Bool {
        !overflowRows(from: rows, limit: limit).isEmpty
    }

    static func visibleDevices<Device>(
        from devices: [Device],
        limit: Int?,
        isExpanded: Bool
    ) -> [Device] {
        guard !isExpanded, let limit else { return devices }
        return Array(devices.prefix(max(0, limit)))
    }

    static func canToggleExpansion<Device>(
        for devices: [Device],
        limit: Int?
    ) -> Bool {
        guard let limit else { return false }
        return devices.count > max(0, limit)
    }
}

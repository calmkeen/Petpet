//
//  overlayPlayer.swift
//  PetPet Watch App
//
//  Created by calmkeen on 9/27/25.
//

import SwiftUI
import AVFoundation
import AVKit

struct OverlayPlayerForTimeRemove: View {
    var body: some View {
        VideoPlayer(player: nil,videoOverlay: { })
        .focusable(false)
        .disabled(true)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

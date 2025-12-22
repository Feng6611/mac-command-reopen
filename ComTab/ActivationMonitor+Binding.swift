//
//  ActivationMonitor+Binding.swift
//  ComTab
//
//  Created by CHEN on 2025/10/31.
//

import SwiftUI

extension ActivationMonitor {
    var featureToggleBinding: Binding<Bool> {
        Binding(
            get: { self.isFeatureEnabled },
            set: { self.isFeatureEnabled = $0 }
        )
    }
}


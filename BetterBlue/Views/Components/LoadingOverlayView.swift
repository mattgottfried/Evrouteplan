//
//  LoadingOverlayView.swift
//  BetterBlue
//
//  Created by Mark Schmidt on 8/25/25.
//

import SwiftUI

struct LoadingOverlayView: View {
    let brandName: String

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            // Loading card
            VStack(spacing: 16) {
                Text("Adding \(brandName) Account")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(1.2)
            }
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
            }
            .padding(.horizontal, 40)
        }
    }
}

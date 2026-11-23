import FinalApproachCore
import SwiftUI

/// Placeholder collection screen. It lists the tiers from the core package,
/// which proves the app links against `FinalApproachCore`.
struct CollectionView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Tiers") {
                    ForEach(Tier.allCases, id: \.self) { tier in
                        Text(tier.displayName)
                    }
                }
                Section("Rarity") {
                    ForEach(Rarity.allCases, id: \.self) { rarity in
                        Text(rarity.displayName)
                    }
                }
            }
            .navigationTitle("Collection")
        }
    }
}

#Preview {
    CollectionView()
}

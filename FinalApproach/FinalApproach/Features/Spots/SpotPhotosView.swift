import SwiftUI

/// The photos other people shared from one spot. A photo whose owner kept
/// the location private never appears here.
struct SpotPhotosView: View {
    let spotID: String

    @Environment(CollectionModel.self) private var model

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        Group {
            if let spot = model.spot(id: spotID) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(spot.photoNames, id: \.self) { name in
                            PhotoFill(imageName: name, description: "A photo taken from \(spot.name)")
                                .frame(height: 146)
                        }
                    }
                    .padding(.top, 8)
                }
                .navigationTitle(spot.name)
            } else {
                ContentUnavailableView(
                    "Spot not found",
                    systemImage: "mappin.slash",
                    description: Text("This spot is no longer listed.")
                )
            }
        }
        .background(Theme.ground)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SpotPhotosView(spotID: "atl-south-approach")
    }
    .environment(SampleData.model())
}

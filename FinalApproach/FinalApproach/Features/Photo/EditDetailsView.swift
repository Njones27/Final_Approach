import SwiftUI

/// Changes the aircraft details of a photo the user logged. It is how an
/// aircraft that was logged without a name gets one later.
struct EditDetailsView: View {
    let photo: SpottedPhoto

    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var aircraftType = ""
    @State private var registration = ""
    @State private var airline = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Leave a field empty if you do not know it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    DetailField(label: "Type", prompt: "Boeing 737-800", text: $aircraftType)
                    // A registration that must stay hidden is never shown,
                    // so it is not offered for editing and is kept as it is.
                    if !photo.hasBlockedRegistration {
                        DetailField(
                            label: "Registration",
                            prompt: "N8642E",
                            text: $registration,
                            capitalization: .characters
                        )
                    }
                    DetailField(label: "Airline", prompt: "Southwest Airlines", text: $airline)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.ground)
            .navigationTitle("Aircraft details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.updateDetails(
                            forPhotoID: photo.id,
                            aircraftType: aircraftType,
                            registration: photo.hasBlockedRegistration ? nil : registration,
                            airline: airline
                        )
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            aircraftType = photo.aircraftType
            registration = photo.visibleRegistration ?? ""
            airline = photo.airline
        }
    }
}

#Preview("Unknown aircraft") {
    let model = SampleData.model()
    model.add(SampleData.unknownAircraftPhoto)
    return EditDetailsView(photo: SampleData.unknownAircraftPhoto)
        .environment(model)
}

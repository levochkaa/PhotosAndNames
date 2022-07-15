import SwiftUI
import MapKit
import PhotosUI
import CoreLocation

class LocationFetcher: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var lastKnownLocation: CLLocationCoordinate2D?

    override init() {
        super.init()
        manager.delegate = self
        self.start()
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastKnownLocation = locations.first?.coordinate
    }
}

struct ImageWithName: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var imageData: Data
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var image: Image? {
        if let uiImage = UIImage(data: imageData) {
            return Image(uiImage: uiImage)
        }
        return nil
    }

    static func ==(lhs: ImageWithName, rhs: ImageWithName) -> Bool {
        lhs.id == rhs.id
    }
}

extension ContentView {
    @MainActor class ViewModel: ObservableObject {

        let savePath = FileManager.documentsDirectory.appendingPathComponent("SavedPhotos")

        @Published private(set) var images: [ImageWithName]

        init() {
            do {
                let data = try Data(contentsOf: savePath)
                images = try JSONDecoder().decode([ImageWithName].self, from: data)
            } catch {
                images = []
            }
        }

        func addImage(image: UIImage, name: String, location: CLLocationCoordinate2D) {
            if let pngData = image.pngData() {
                let newImage = ImageWithName(id: UUID(), name: name, imageData: pngData, latitude: location.latitude, longitude: location.longitude)
                images.append(newImage)
                save()
            }
        }

        func save() {
            do {
                let data = try JSONEncoder().encode(images)
                try data.write(to: savePath, options: [.atomic, .completeFileProtection])
            } catch {
                print("Unable to save data.")
            }
        }
    }
}

struct ContentView: View {

    let locationFetcher = LocationFetcher()

    @State private var inputImage: UIImage?
    @State private var showingImagePicker = false

    @StateObject private var viewModel = ViewModel()

    var body: some View {
        NavigationView {
            List(viewModel.images) { image in
                if let wrappedImage = image.image {
                    NavigationLink(destination: PhotosNamesDetailView(imageWithName: image)) {
                        HStack {
                            wrappedImage
                                .resizable()
                                .frame(width: 40, height: 40)
                            Text(image.name)
                        }
                    }
                }
            }
            .navigationTitle("Photos & Names")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingImagePicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $inputImage)
        }
        .onChange(of: inputImage) { _ in
            if let image = inputImage {
                alertTextField(title: "Image name", message: "Please enter name for the imported image", hintText: "Unknown", primaryTitle: "Enter", secondaryTitle: "Cancel", primaryAction: { text in
                    if let location = self.locationFetcher.lastKnownLocation {
                        viewModel.addImage(image: image, name: text == "" ? "Unknown" : text, location: location)
                    }
                }, secondaryAction: {
                    //
                })
            }
        }
    }
}

struct Annotation: Identifiable {
    var id = UUID()
}

struct PhotosNamesDetailView: View {

    let locations = [Annotation()]

    @State var imageWithName: ImageWithName
    @State private var mapRegion: MKCoordinateRegion

    init(imageWithName: ImageWithName) {
        _imageWithName = State(wrappedValue: imageWithName)
        _mapRegion = State(wrappedValue: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: imageWithName.latitude, longitude: imageWithName.longitude), span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)))
    }

    var body: some View {
        VStack {
            imageWithName.image?
                .resizable()
                .scaledToFit()
            Map(coordinateRegion: $mapRegion, annotationItems: locations) { _ in
                MapMarker(coordinate: imageWithName.coordinate)
            }
        }
        .navigationTitle(imageWithName.name)
    }
}

struct ImagePicker: UIViewControllerRepresentable {

    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        //
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    self.parent.image = image as? UIImage
                }
            }
        }

        var parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }
    }
}

extension View {
    func alertTextField(title: String, message: String, hintText: String, primaryTitle: String, secondaryTitle: String, primaryAction: @escaping (String) -> (), secondaryAction: @escaping () -> ()) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = hintText
        }
        alert.addAction(.init(title: secondaryTitle, style: .cancel, handler: { _ in
            secondaryAction()
        }))
        alert.addAction(.init(title: primaryTitle, style: .default, handler: { _ in
            if let text = alert.textFields?[0].text {
                primaryAction(text)
            } else {
                primaryAction("")
            }
        }))
        rootController().present(alert, animated: true, completion: nil)
    }
    func rootController() -> UIViewController {
        guard let screen = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return .init()
        }
        guard let root = screen.windows.first?.rootViewController else {
            return .init()
        }
        return root
    }
}

extension FileManager {
    static var documentsDirectory: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.dark)
    }
}

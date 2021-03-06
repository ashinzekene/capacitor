import Foundation
import Photos

@objc(CAPCameraPlugin)
public class CAPCameraPlugin : CAPPlugin, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIPopoverPresentationControllerDelegate {
  var imagePicker: UIImagePickerController?
  var call: CAPPluginCall?
  
  var imageCounter = 0
  
  var resultType: String = "base64"
  var quality: Float = 1.0
  var width: Float = 0
  var height: Float = 0
  var shouldResize = false
  var shouldCorrectOrientation = false
  
  @objc func getPhoto(_ call: CAPPluginCall) {
    self.call = call
    self.quality = call.get("quality", Float.self, 100)!
    let allowEditing = call.get("allowEditing", Bool.self, false)!
    self.resultType = call.get("resultType", String.self, "base64")!
    // Get the new image dimensions if provided
    self.width = Float(call.get("width", Int.self, 0)!)
    self.height = Float(call.get("height", Int.self, 0)!)
    if self.width > 0 || self.height > 0 {
      // We resize only if a dimension was provided
      shouldResize = true
    }
    
    self.shouldCorrectOrientation = call.get("correctOrientation", Bool.self, false)!
    
    // Make sure they have all the necessary info.plist settings
    if let missingUsageDescription = checkUsageDescriptions() {
      bridge.modulePrint(self, missingUsageDescription)
      call.error(missingUsageDescription)
      bridge.alert("Camera Error", "Missing required usage description. See console for more information")
      return
    }
    
    imagePicker = UIImagePickerController()
    imagePicker!.delegate = self
    imagePicker!.modalPresentationStyle = .popover
    imagePicker!.popoverPresentationController?.delegate = self
    self.setCenteredPopover(self.imagePicker!)
    //imagePicker!.popoverPresentationController?.sourceView = view
    
    DispatchQueue.main.async {
      
      // Build the action sheet
      let alert = UIAlertController(title: "Photo", message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)
      alert.addAction(UIAlertAction(title: "From Photos", style: .default, handler: { (action: UIAlertAction) in
        let photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus()
        if photoAuthorizationStatus == .restricted || photoAuthorizationStatus == .denied {
          call.error("User denied access to photos")
          return
        }
        
        self.imagePicker!.sourceType = .photoLibrary
        self.imagePicker!.allowsEditing = allowEditing

        self.bridge.viewController.present(self.imagePicker!, animated: true, completion: nil)
      }))
      
      alert.addAction(UIAlertAction(title: "Take Picture", style: .default, handler: { (action: UIAlertAction) in
        if self.bridge.isSimulator() || !UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.camera) {
          self.bridge.modulePrint(self, "Camera not available in simulator")
          self.bridge.alert("Camera Error", "Camera not available in Simulator")
          call.error("Camera not available while running in Simulator")
          return
        }
        
        self.imagePicker!.sourceType = .camera

        self.bridge.viewController.present(self.imagePicker!, animated: true, completion: nil)
      }))
      
      alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action: UIAlertAction) in
        alert.dismiss(animated: true, completion: nil)
      }))
      
      self.setCenteredPopover(alert)
      self.bridge.viewController.present(alert, animated: true, completion: nil)
    }
  }
  
  public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
  }
  
  public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
    var image: UIImage?
    
    if let editedImage = info[UIImagePickerControllerEditedImage] as? UIImage {
      // Use editedImage Here
      image = editedImage
    } else if let originalImage = info[UIImagePickerControllerOriginalImage] as? UIImage {
      // Use originalImage Here
      image = originalImage
    }
    
    if shouldResize {
      guard let convertedImage = resizeImage(image!) else {
        self.call?.error("Error resizing image")
        return
      }
      image = convertedImage
    }
    
    if shouldCorrectOrientation {
      guard let convertedImage = correctOrientation(image!) else {
        self.call?.error("Error resizing image")
        return
      }
      image = convertedImage
    }
    
    guard let jpeg = UIImageJPEGRepresentation(image!, CGFloat(quality/100)) else {
      print("Unable to convert image to jpeg")
      self.call?.error("Unable to convert image to jpeg")
      return
    }

    if resultType == "base64" {
      let base64String = jpeg.base64EncodedString()
      
      self.call?.success([
        "base64_data": "data:image/jpeg;base64," + base64String,
        "format": "jpeg"
      ])
    } else if resultType == "uri" {
      let path = try! saveTemporaryImage(jpeg)
      call?.success([
        "path": path,
        "format": "jpeg"
      ])
    }
    
    picker.dismiss(animated: true, completion: nil)
  }
  
  func resizeImage(_ image: UIImage) -> UIImage? {
    let isAspectScale = self.width > 0 && self.height == 0 || self.height > 0 && self.width == 0
    let aspect = Float(image.size.width / image.size.height);

    var size = CGSize.init(width: Int(self.width), height: Int(self.height))
    if isAspectScale {
      if self.width > 0 {
        size = CGSize.init(width: Int(self.width), height: Int(self.width * (1/aspect)))
      } else if self.height > 0 {
        size = CGSize.init(width: Int(self.height * (1/aspect)), height: Int(self.height))
      }
    }

    UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
    image.draw(in: CGRect(origin: CGPoint.zero, size: size))
    
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return scaledImage
  }
  
  func correctOrientation(_ image: UIImage) -> UIImage? {
    UIGraphicsBeginImageContext(image.size)
    image.draw(at: .zero)
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return newImage ?? image
  }
  
  func saveTemporaryImage(_ data: Data) throws -> String {
    var url: URL
    repeat {
      imageCounter += 1
      url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("photo-\(imageCounter).jpg")
    } while FileManager.default.fileExists(atPath: url.absoluteString)
    
    try data.write(to: url, options: .atomic)
    return url.absoluteString
  }
  
  /**
   * Make sure the developer provided proper usage descriptions
   * per apple's terms.
   */
  func checkUsageDescriptions() -> String? {
    if let dict = Bundle.main.infoDictionary {
      let hasPhotoLibraryAddUsage = dict["NSPhotoLibraryAddUsageDescription"] != nil
      if !hasPhotoLibraryAddUsage {
        let docLink = DocLinks.NSPhotoLibraryAddUsageDescription
        return "You are missing NSPhotoLibraryAddUsageDescription in your Info.plist file." +
        " Camera will not function without it. Learn more: \(docLink.rawValue)"
      }
      let hasPhotoLibraryUsage = dict["NSPhotoLibraryUsageDescription"] != nil
      if !hasPhotoLibraryUsage {
          let docLink = DocLinks.NSPhotoLibraryUsageDescription
          return "You are missing NSPhotoLibraryUsageDescription in your Info.plist file." +
          " Camera will not function without it. Learn more: \(docLink.rawValue)"
      }
      let hasCameraUsage = dict["NSCameraUsageDescription"] != nil
      if !hasCameraUsage {
          let docLink = DocLinks.NSCameraUsageDescription
          return "You are missing NSCameraUsageDescription in your Info.plist file." +
          " Camera will not function without it. Learn more: \(docLink.rawValue)"
      }
    }
    
    return nil
  }
  
}

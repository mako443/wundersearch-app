//
//  SearchHandler.swift
//  WunderSearch
//
//  Created by maurice on 18.06.21.
//

import Foundation
import Photos
import UIKit
import CoreML
import Vision

class SearchHandler {
    let manager = PHImageManager.default()
    var indexedImages: [String: MLMultiArray] = [:] // [localIdentifier: imageDescriptor]
    var numberOfImages: Int = 0
    
    var imageEncoder: VNCoreMLModel
    var textEncoder: TextEncoder
    var knownWords: Dictionary<String, Int> = [:]
    let maxEncodeWords = 32
    
    init(){
        // Load models
        self.imageEncoder = try! VNCoreMLModel(for: ImageEncoder().model)
        self.textEncoder = TextEncoder()
        
        // Load known words
        let path = Bundle.main.path(forResource: "known_words", ofType: "json")
        if path == nil {
            fatalError("known_words.json not found.")
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path!), options: .mappedIfSafe)
            let jsonResult = try JSONSerialization.jsonObject(with: data, options: .mutableLeaves)
            self.knownWords = jsonResult as! Dictionary<String, Int>
        } catch {
            print(error)
        }
        
        // Load previously indexed images
        self.loadIndexedImages()
        
        // Encode the test image to verify model outputs
        if(false) {
            let image: UIImage = #imageLiteral(resourceName: "test-image")
            print(image.size)
            let ciImage = CIImage(cgImage: image.cgImage!)
            self.encodeImage(model: self.imageEncoder, image: ciImage, localIdentifier: "test-image")
        }
    }
    
    // TODO: care to re-index images on model update
    func loadIndexedImages(){
        let userDefaults = UserDefaults.standard
        if let loadedDescriptors = userDefaults.object(forKey: "image_descriptors") as? [String:[Float]] {
            for (id, descriptor) in loadedDescriptors {
                self.indexedImages[id] = try! MLMultiArray(descriptor)
            }
        } else {
            print("image descriptors could not be loaded.")
        }
    }
    
    func saveIndexedImages(){
        let userDefaults = UserDefaults.standard
        var saveDescriptors: [String:[Float]] = [:]
        for (id, descriptor) in self.indexedImages{
            saveDescriptors[id] = Array(try! UnsafeBufferPointer<Float>(descriptor))
        }
        userDefaults.set(saveDescriptors, forKey: "image_descriptors")
        print("Saved indexed images.")
    }
    
    func dotProduct(a: MLMultiArray, b: MLMultiArray) -> Float {
        assert(a.count == b.count, "Inputs need to be of equal sizes.")
        assert((a.dataType == b.dataType) && (a.dataType == MLMultiArrayDataType.float32), "Unexpected or mismatching input data types.")
        
        let ptrA = UnsafePointer<Float32>(OpaquePointer(a.dataPointer))
        let ptrB = UnsafePointer<Float32>(OpaquePointer(b.dataPointer))
        
        var prod: Float = 0
        for i in 0..<a.count{
            prod += ptrA[i] * ptrB[i]
        }
        return prod
    }
    
    private func getTopKPhotos(textDescriptor: MLMultiArray, k: Int = 25) -> [UIImage]{
        var scoresDict: [String: Float] = [:] // [localIdentifier: score]
        for (id, imageDescriptor) in self.indexedImages {
            scoresDict[id] = self.dotProduct(a: textDescriptor, b: imageDescriptor)
        }
        
        // Sort by scores descending
        let sorted = scoresDict.sorted(by: { (keyVal1, keyVal2) -> Bool in
            keyVal1.value > keyVal2.value
        })
        
        // Extract the top-k local identifiers
        var topKIds: [String] = []
        for i in 0..<min(sorted.count, k){
            topKIds.append(sorted[i].key)
        }
        
        // Retrieve the images by their identifiers
        var topKImages: [UIImage] = []
        
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true
        requestOptions.deliveryMode = .highQualityFormat
        
        let results: PHFetchResult = PHAsset.fetchAssets(withLocalIdentifiers: topKIds, options: PHFetchOptions())
        for i in 0..<results.count {
            let asset = results.object(at: i)
            let size = CGSize(width: 500, height: 500)

            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: requestOptions) { (image, infoDict) in
                if let image = image {
                    topKImages.append(image)
                }
                else {
                    print("Image is nil.")
                }
            }
        }
        
        return topKImages
    }
    
    func searchPhotos(text: String, topK: Int) -> [UIImage] {
        let textSplit = text.lowercased().components(separatedBy: " ")
        
        do {
            let inputArray = try MLMultiArray(shape: [1, 32], dataType: MLMultiArrayDataType.float32)
            for i in 0..<min(textSplit.count, 32){
                inputArray[i] = 2.0 // TODO: load actual index dict and make dictionary variable size
            }
            
            let output = try! textEncoder.prediction(input_1: inputArray)
            let textDescriptor = output._64
            print(textDescriptor.shape)
            
            var topKPhotos = self.getTopKPhotos(textDescriptor: textDescriptor)
            print("Num photos: \(topKPhotos.count)")
            return topKPhotos
        }
        catch {
            print(error)
            return []
        }
    }
    
    /// Encode an image for searching by queuing a VNCoreMLRequest and adding the image descriptor to indexedImages on completion.
    /// TODO: Ok to queue many images? Rather queue all at once in handler.perform? Async ok?
    /// - Parameters:
    ///   - model: The image encoder model
    ///   - image: The image to encode
    ///   - localIdentifier: localIdentifier of the image to encode
    func encodeImage(model: VNCoreMLModel, image: CIImage, localIdentifier: String){
        let request = VNCoreMLRequest(model: model) { (request, error) in
            guard let results = request.results as? [VNCoreMLFeatureValueObservation] else {
                fatalError("Model failed to process image.")
            }
//            print(results[0].featureName)
            guard let imageDescriptor = results[0].featureValue.multiArrayValue else {
                fatalError("Could not access image descriptor array.")
            }
//            print(imageDescriptor.shape)
            self.indexedImages[localIdentifier] = imageDescriptor
            print("\(self.indexedImages.count) images encoded")
            
            if localIdentifier == "test-image" {
                print("Test image descriptor:")
                print(imageDescriptor)
            }
        }
        
        let handler = VNImageRequestHandler(ciImage: image)
        do {
            try handler.perform([request])
        }
        catch {
            print(error)
        }
    }
    
    func indexPhotos() {
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .fastFormat
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let results: PHFetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
//        let ids = ["CC95F08C-88C3-4012-9D6D-64A413D254B3/L0/001", "ED7AC36B-A150-4C38-BB8C-B6D696F4F2ED/L0/001"]
//        let results: PHFetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: fetchOptions)

        print("Number of photos: \(results.count)")
        
        if results.count > 0 {
            self.numberOfImages = results.count
            
            for i in 0..<results.count {
                let asset = results.object(at: i)
                let size = CGSize(width: 500, height: 500)
//                print(asset.localIdentifier)
                
                // Currently skipping already encoded images
                // TODO: possibly verify a checksum to check for updated images
                if self.indexedImages[asset.localIdentifier] != nil {
                    print("Skipping image \(asset.localIdentifier)")
                    continue
                }

                manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: requestOptions) { (image, infoDict) in
                    if let image = image {
                        let ciImage = CIImage(cgImage: image.cgImage!)
                        self.encodeImage(model: self.imageEncoder, image: ciImage, localIdentifier: asset.localIdentifier)
                    }
                    else {
                        print("Image is nil.")
                    }
                    
                    // Once all images are indexed, save them to UserDefaults TODO: find a better trigger for this
                    if i == results.count - 1 {
                        self.saveIndexedImages()
                    }
                }
            }
        }
    }
}

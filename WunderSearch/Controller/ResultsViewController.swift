//
//  ResultsViewController.swift
//  WunderSearch
//
//  Created by maurice on 23.06.21.
//

import UIKit

private let reuseIdentifier = "ResultCellIdentifier"

class ResultsViewController: UICollectionViewController {
    let sectionInsets = UIEdgeInsets(top: 50.0, left: 20.0, bottom: 50.0, right: 20.0)
    var searchResults: [UIImage] = []
    let itemsPerRow: CGFloat = 3
    
    var searchHandler: SearchHandler = SearchHandler()
    
    @IBOutlet weak var searchField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Register cell classes
        self.collectionView!.register(UICollectionViewCell.self, forCellWithReuseIdentifier: reuseIdentifier)
        
        searchHandler.indexPhotos()
    }
    
    @IBAction func searchTapped(_ sender: UIBarButtonItem) {
        searchResults.removeAll()
        
        if searchField.text != nil{
            let resultImages = searchHandler.searchPhotos(text: searchField.text!, topK: 25)
            searchResults.append(contentsOf: resultImages)
        } else {
            print("Text empty")
        }
        
        self.collectionView.reloadData()
    }
}

extension ResultsViewController {
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.searchResults.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let paddingSpace = sectionInsets.left * (itemsPerRow + 1)
        let availableWidth = view.frame.width - paddingSpace
        let widthPerItem = availableWidth / itemsPerRow
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath)
        cell.backgroundColor = .white
        cell.contentView.subviews.forEach({ $0.removeFromSuperview() }) // Remove old image views as cell might be re-used
        
        let imageView: UIImageView = UIImageView(frame: CGRect(x: 0, y: 0, width: widthPerItem, height: widthPerItem))
        imageView.contentMode = UIImageView.ContentMode.scaleAspectFit
        imageView.image = searchResults[indexPath.row]
        cell.contentView.addSubview(imageView)
        return cell
    }
}

extension ResultsViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let paddingSpace = sectionInsets.left * (itemsPerRow + 1)
        let availableWidth = view.frame.width - paddingSpace
        let widthPerItem = availableWidth / itemsPerRow
        
        return CGSize(width: widthPerItem, height: widthPerItem)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return sectionInsets
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return sectionInsets.left
    }
}
